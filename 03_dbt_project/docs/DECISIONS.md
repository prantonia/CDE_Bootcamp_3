# Engineering decisions and the reasoning behind them

This is the decision log for the Marketing Data Platform. Each entry says what was decided, why, what it
costs, and what the alternatives were. It follows the questions in section 20 of the brief and then covers
the supporting decisions (ingestion, tooling, security).

For *what* was built see the [README](../README.md); for *how to run it* see the [runbook](RUNBOOK.md).

---

## 1. Model structure

**Decision.** Three layers inside dbt, plus a seed:

| Layer | Models | Materialization |
|---|---|---|
| Staging | `stg_facebook_ads__*` (5), `stg_snapchat_ads__*` (4) | view |
| Intermediate | `int_facebook_ads__performance`, `int_snapchat_ads__performance` | ephemeral |
| | `int_marketing_ads` | view |
| Marts | `fct_marketing_ad_performance_daily` | incremental (merge) |
| | `dim_marketing_ads`, `rpt_marketing_campaign_daily`, `rpt_marketing_platform_monthly` | table |
| Reference | `fx_rates_to_eur` | seed |

**Why.**
- **Staging is 1:1 with each source table** and does only cheap, safe work: rename, cast, trim, turn the text
  `'null'` into a real `NULL`. Nothing analytical happens here, so a staging bug is easy to find.
- **Platform differences are resolved in exactly one place**: the two per-platform intermediates map each
  platform onto a shared column set, and `int_marketing_ads` unions them. Downstream models never need to
  know which platform a column came from, which is the brief's central requirement.
- **A wide fact plus reports, rather than a star of many dimensions.** The consumers are analysts, BI tools and
  an AI agent. Few joins and unambiguous column names make wrong answers harder. The fact carries the
  descriptive attributes (campaign, ad group, account names) directly; `dim_marketing_ads` exists for
  consumers that want one row per ad.
- **Report models hold the ratios** (CTR, CPC, CPM). Nobody has to remember how to compute them, and they
  are computed once, correctly (see section 4).

**Trade-off.** The wide fact repeats descriptive text on every row. At this volume (about 95k rows) that is
cheap; at a much larger scale I would split the descriptive columns out into dimensions joined at query time.

**Alternatives considered.** One `stg_facebook_ads` and one `stg_snapchat_ads` model, as the brief's examples
suggest. I kept staging per source table instead, because the sources have several files each (stats, ads,
ad groups, campaigns, accounts) with different grains, and joining them inside a "staging" model would hide
the grain.

---

## 2. Grain and keys

| Model | Grain | Key |
|---|---|---|
| `stg_facebook_ads__ad_stats` | one Facebook ad on one day | (`ad_id`, `report_date`) |
| `stg_snapchat_ads__ad_stats` | one Snapchat ad on one day in one country | (`ad_id`, `report_date`, `country_code`) |
| `int_marketing_ads`, `fct_marketing_ad_performance_daily` | one ad on one day in one country, per platform | `performance_key` |
| `dim_marketing_ads` | one ad per platform | `ad_key` |
| `rpt_marketing_campaign_daily` | one campaign, platform and currency on one day | those four columns |
| `rpt_marketing_platform_monthly` | one platform in one month | (`report_month`, `platform`) |

**Why this grain.** It is the finest grain both platforms can support. Facebook reports per ad per day and has no
country; Snapchat reports per ad per day per country. Aggregating Snapchat up to ad-day would have thrown
away information the business may want, while the finer grain loses nothing: Facebook rows simply carry the
country `UNSPECIFIED`, so the key never contains a `NULL`.

**Keys.** Surrogate keys are built with `dbt_utils.generate_surrogate_key` from the **platform plus the source
id**. Including the platform matters: a Facebook id and a Snapchat id could in principle collide, and a key
that is only unique within one platform would not be unique in the union. Source ids are kept as **strings**,
because Snapchat uses UUIDs and Facebook uses 13 to 18 digit numbers that would overflow some numeric types.

---

## 3. How platform differences are handled

| Difference | Handling |
|---|---|
| Snapchat names the ad id `ad_detail_id` | renamed to `ad_id` in staging |
| Different id formats (UUID vs numeric) | both kept as strings |
| Facebook has no country | `UNSPECIFIED` in the intermediate |
| Snapchat has no account table or ad status | `NULL`, documented as such in the model docs |
| Snapchat ad-group history has several versions per ad group | reduced to the latest version with `qualify row_number()`; joining all versions would multiply fact rows |
| The text `'null'` for clicks and impressions | converted to a real `NULL` |
| Mixed currencies (Facebook EUR and USD accounts, Snapchat EUR) | native `spend` plus `currency_code`, and `spend_eur` using the `fx_rates_to_eur` seed |

**Why keep both native and EUR spend.** Native spend is the number the platform billed; EUR spend is what
makes platforms comparable. Hiding the original behind a conversion would make audits harder.

**Known limitation.** The USD to EUR rate in the seed is a **placeholder (0.92)**, flagged in the seed itself.
It must be replaced with a finance-approved rate before `spend_eur` is used for reporting. A real
implementation would use dated rates, so each day converts at that day's rate.

---

## 4. Null handling and metric definitions

**Unknown is not zero.** When the platform did not report clicks or impressions, the value is `NULL`, not `0`.
A zero would claim "nobody clicked", which would pull CTR and CPC in the wrong direction. This is the single
most important data-quality decision in the project.

**Ratios are computed from sums, never averaged.** The portfolio CTR is the total clicks divided by the total
impressions, not the average of daily CTRs. Averaging ratios weights a day with 10 impressions the same as a day
with 10 million and gives a wrong answer.

**Only rows where the inputs were reported count.** For CTR, both clicks and impressions must be present; a row
with missing clicks would otherwise add impressions to the denominator without adding clicks to the numerator.

**Zero denominators return `NULL`**, via the `safe_divide` macro. A CPC with no clicks is undefined, not zero
and not infinite. This is what the brief asks for when it says to handle zero clicks and zero impressions.

| Metric | Definition |
|---|---|
| CTR | clicks / impressions |
| CPC | spend / clicks |
| CPM | spend / impressions x 1,000 |

---

## 5. Materializations

The brief says not to make everything a view or a table, so each choice is deliberate:

| Model | Choice | Reason |
|---|---|---|
| Staging | **view** | Cheap renames and casts; no storage; always reflects the latest bronze. |
| Per-platform intermediates | **ephemeral** | Used by exactly one model each; inlined as a CTE, so no object is created and nothing extra to maintain. |
| `int_marketing_ads` | **view** | It has two consumers (fact and dimension) that each store their own result; a third copy would cost storage and add no speed. |
| `fct_marketing_ad_performance_daily` | **incremental, merge** | The largest and most-read model; history rarely changes; see section 6. |
| `dim_marketing_ads`, `rpt_*` | **table** | Small, queried constantly by BI and the agent, so computing them once per run beats recomputing them per query. |
| `fx_rates_to_eur` | **seed** | A tiny, version-controlled lookup that changes rarely and needs review. |

---

## 6. Why the fact model is incremental

- **Volume and pattern.** Ad performance is append-mostly: each run adds new days.
- **Restatements.** Ad platforms revise the most recent days (late conversions, spend corrections). A plain
  append would duplicate those days and a high-water-mark filter would never pick up the corrections.
- **Strategy.** `merge` on `performance_key`, re-processing the trailing `incremental_lookback_days` (default 7).
  Merging on a stable key means re-running a day replaces its rows instead of duplicating them, so the model is
  idempotent.
- **Full refresh stays available** (`dbt build --full-refresh`) for logic changes and for restatements older than
  the lookback window.

**Known trade-off.** A merge cannot delete rows that a platform removed at the source. Those stay until the next
full refresh. For ad spend this is acceptable and documented.

---

## 7. Data quality tests

The tests are chosen to protect specific failure modes, not to hit a coverage number.

| Test type | Where | What it protects against |
|---|---|---|
| `unique` and `not_null` on keys | every model | duplicate or missing keys that would silently distort sums |
| `accepted_range` (spend, impressions, clicks >= 0) | staging and fact | sign errors and corrupt exports |
| `clicks <= impressions` and CTR between 0 and 1 | fact and reports | swapped columns |
| `accepted_values` (platform, ad status) | fact, dimension | a third platform or a new status appearing unannounced |
| `relationships` | across the model chain | orphaned ads, campaigns, accounts |
| currency must exist in the FX seed | fact | a new currency silently converting to `NULL` spend |
| **Reconciliation** (fact vs staging, reports vs fact) | singular tests | join fan-out, dropped rows, incremental drift. These catch the bugs that single-column tests cannot. |
| No future report dates | singular test | broken date parsing |
| Share of missing metrics | singular test, **warn** | an export that suddenly has far more missing clicks |

**Severity.** Hard failures are used where the data would be wrong. Two checks are deliberately `warn`:
- The Snapchat `relationships` test between ads and ad groups returns a few hundred rows: Snapchat ads reference ad
  groups that are not in the ad-group history. This is a real source data gap, not a modelling bug. Failing the
  build on it would block every release for something the team cannot fix; a warning keeps it visible.
- The missing-metrics share warns, because the baseline (about 26% missing clicks on Facebook, 4% on Snapchat) is
  normal and only a jump matters.

---

## 8. Source freshness

Every bronze source is configured with `loaded_at_field: _loaded_at` and a `warn_after` of 2 days, plus an
`owner` in `meta` and `enabled: true`. Run with `dbt source freshness`.

**Why `_loaded_at`.** The ingestion loader stamps it on every (re)load, so it is the one timestamp that exists
on every bronze table and does not depend on a source column.

**What it actually measures.** Because ingestion skips unchanged files, `_loaded_at` moves only when a Drive file
changes. The check therefore answers "has any new data arrived in the last 2 days?". For a daily export that is
exactly the signal wanted, and a stalled export raises a warning. For the static sample files used here it will
warn two days after the first load, which is correct behaviour, not a fault. In a real deployment the threshold
should match the delivery schedule of the exports.

---

## 9. Documentation and observability

- Every source, model and important column has a description, including the grain of each model and the
  meaning of `NULL` where it matters. Metrics are defined in a docs block shared by the models that use them.
- `dbt docs generate --static` produces a single HTML file with the lineage graph; CI publishes it on every run,
  and a committed copy lives in `docs/site/`.
- `docs/DATA_DICTIONARY.md` is **generated** from dbt's manifest and catalog, so it cannot drift from the models.
- **Elementary** records every test result and run, and adds volume-anomaly and schema-change tests. The
  `edr report` HTML gives the team a health dashboard and a history of failures. This is what turns "tests pass
  today" into "we can see the project's health over time".

---

## 10. Environments: three, not four

**Decision.** Three environments, each with its own target, identity and location:

| Environment | Purpose | dbt target | Identity | Where models land |
|---|---|---|---|---|
| **Development** | a developer builds and tests a change | `dev` | the developer (personal token) | `dev_sandbox.dbt_<name>` |
| **CI** | automated validation of every pull request | `ci` | CI service principal | `ci_development.PR_<number>` (dropped on PR close) |
| **Production** | the models consumers use | `production` | production service principal | `silver_production.*`, `gold_production.*` |

**Why no separate staging environment.** The brief asks for "Development / Staging", meaning one pre-production
environment, which development provides. A fourth environment would add two catalogs, a service principal,
a GitHub environment and a workflow for very little benefit here:
- There is **one raw source**. A staging copy of the gold tables would be built from the same bronze data as
  production, so it would show the same numbers and expose no new data problems.
- **CI already tests the exact change on production-shaped data** in an isolated schema before merge, with the
  full test suite, so most of what a staging deploy would catch is caught there.
- Every extra environment is more credentials to rotate and more infrastructure to keep in step with production.

**What this costs.** There is no long-lived, stable pre-production copy for stakeholders to review before a
release, and the production service principal's exact permissions are first exercised in production. I would add
a staging environment when several consumers depend on production and need to preview changes, or when deploys
get risky enough to justify rehearsing them.

**Catalog layout.** Five catalogs: `bronze_production`, `silver_production`, `gold_production`,
`ci_development`, `dev_sandbox`. Production is split by medallion layer so permissions can be set per layer:
only the ingestion principal may write bronze, the dbt principals may only read it, and analysts may only read
gold. CI and development use one disposable schema each, which is trivial to drop. The `generate_database_name`
and `generate_schema_name` macros route models by target.

---

## 11. Securing production

- **Production authenticates as a Databricks service principal with OAuth** (machine-to-machine client
  credentials). The `production` target in `profiles.yml` has no token option, so a personal access token cannot
  be used there by accident. The pipeline does not depend on any individual's account.
- **A separate ingestion principal** is the only identity that can write bronze. The dbt principals have
  `SELECT` on bronze, so a transformation job cannot alter or overwrite raw data.
- **Least privilege.** Principals get only the catalogs and schemas they need. No principal has
  `CREATE CATALOG` on the metastore (the brief's example grants it): catalogs are created once by an administrator
  in the setup script, and pipelines never need to create them.
- **Service principals are not admins.** Admin rights would let a leaked pipeline secret reach the whole workspace.
- **Secrets** live in GitHub environment secrets (credentials) and a Databricks secret scope (the Drive key).
  Nothing sensitive is in the repository. The `production` GitHub environment is restricted to the `main` branch,
  so only reviewed, merged code can use the production credentials.
- **Personal access tokens are used only in development**, for a developer's own sandbox.

---

## 12. CI/CD

```
feature branch -> pull request -> CI -> merge to main -> production run
```

- **Pull request.** Parse the project and lint the SQL (no warehouse needed), then run a **slim build**
  (`state:modified+`) of only the changed models and their downstream models into `ci_development.PR_<n>` as the
  CI service principal. Unchanged upstream models are reused from production (`--defer`), which keeps CI fast
  and cheap. `dbt build` runs both the models and their tests, and docs are generated.
- **Merge to `main`.** The production workflow runs `dbt build` as the production service principal, then
  generates docs, runs source freshness, publishes the manifest (which the next CI run compares against), and
  produces the Elementary report. It also runs daily to pick up new data, and can be started manually with
  an optional full refresh.
- **Cleanup.** Closing a PR drops its disposable schema.
- **One reusable workflow** is called by every environment, so CI and production run identical steps and differ
  only by inputs. That removes "it passed in CI but production runs something different".
- **Why GitHub Actions for dbt but a Databricks Job for ingestion.** dbt only needs a SQL connection, which
  GitHub runners have. The loader writes Unity Catalog tables and the landing volume, which needs a Databricks
  runtime (`spark` and `dbutils`).

---

## 13. Moving data from Google Drive to Databricks

**Decision.** A small Python package (`marketing_ingest`) lists the Drive folders, compares each file's MD5 to a
manifest table, and reloads only files that are new or changed. Nothing identifying (folder links, file and table
names) is hard-coded: it lives in `config/ingestion.yaml`.

**Why a content-hash manifest.** The Drive API returns each file's MD5 **without downloading it**, so an
unchanged run costs only a metadata call and does no downloading, loading or writing.

**Why replace rather than append.** Each bronze table is rebuilt from its file with an atomic
`CREATE OR REPLACE TABLE`. Readers see the old table or the new one, never a half-loaded one, and re-running
cannot create duplicates.

**Why bronze keeps every column as a string.** Raw data should be stored exactly as received. Typing is a
transformation decision and lives in dbt staging, where it is reviewed, tested and versioned. A bad value in a
numeric column cannot cause the load to fail.

**Alternatives considered.** `COPY INTO` is also idempotent, but it works on files already in cloud storage and
would still need every file downloaded first. Auto Loader suits continuous streams of new files; this source is
a handful of files that are replaced in place.

---

## 14. Tooling: uv

One `pyproject.toml` and `uv.lock` pin dbt, Elementary and the ingestion package identically on a laptop, in CI
and on Databricks. CI installs with `uv sync --frozen`, which fails if the lockfile is stale. The ingestion
package declares only its three small dependencies, so the Databricks notebook never installs dbt and leaves
the cluster's own libraries alone; the transformation tools are a separate dependency group.

---

## 15. Idempotency, end to end

| Stage | Why a re-run is safe |
|---|---|
| Ingestion | unchanged files are skipped; changed files replace their table atomically; a dropped table is rebuilt |
| Staging, intermediate, dimensions, reports | rebuilt from scratch on every run |
| Fact | merge on a stable key over a lookback window |

Running ingestion and dbt any number of times with the same source files produces identical gold tables. The
ingestion logic is covered by unit tests: a first run loads everything, a second run does nothing, a changed file
reloads only its table, and a dropped table heals itself.

---

## 16. Built for analysts, BI and an AI agent

- Names are unambiguous and consistent (`report_date`, `spend`, `spend_eur`, `platform`); the same column means
  the same thing in every model.
- Every column documents its units and what `NULL` means, so an agent does not have to guess.
- Ratios are pre-computed correctly, so a question like "what was Facebook's CPC last month?" cannot be answered
  with an average of averages.
- Consumers read only `gold_production.marketing`; they need no knowledge of either platform's schema.
- The tests and Elementary make it possible to say how far the numbers can be trusted.

---

## 17. Known limitations and next steps

- USD to EUR is a **placeholder rate** and should become a dated, finance-approved rate table.
- Dimension files carry one row per id with no history, so there is no slowly-changing-dimension tracking.
- A merge does not remove rows deleted at the source; a full refresh does.
- The Snapchat ad-to-ad-group gap is surfaced as a warning but not resolved, because the missing ad groups are not
  in the source.
- Freshness and Elementary results are visible in reports but not yet wired to alerting (Slack, e-mail).
- Facebook data is from 2025 and Snapchat data from 2024, so the sample has no month where both platforms overlap.
