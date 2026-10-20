# Marketing Data Platform — Facebook + Snapchat on Databricks & dbt

A small, production-minded platform that turns raw Facebook Ads and Snapchat Ads extracts into **one
governed, documented, tested dataset** for analysts, BI tools and AI agents.

```
Google Drive (source)  ──►  Databricks bronze  ──►  dbt (silver → gold)  ──►  Analysts · BI · AI agent
   public folders            Unity Catalog            staging/int/marts
```

- **Python & tooling managed by [uv](https://docs.astral.sh/uv/)** — one lockfile, one `uv sync`, reproducible everywhere.
- **The whole pipeline is idempotent** — re-running ingestion or dbt converges to the same state and does no redundant work.
- Raw data moves **from Google Drive to Databricks** by an idempotent loader; all transformation happens in Databricks with dbt.
- dbt tests protect the model, **Elementary** monitors it, **dbt docs** + a generated **data dictionary** explain it.
- **Three environments** — development, CI and production. **GitHub Actions** validates every PR in a throwaway schema
  and deploys `main` to production as a **Databricks service principal** (no personal access token in CI/CD).

> **Why it is built this way:** every major choice (grain, keys, materializations, incremental strategy, tests,
> environments, security, CI/CD) is explained in **[`docs/DECISIONS.md`](docs/DECISIONS.md)**.
> **To run it for real:** follow **[`docs/RUNBOOK.md`](docs/RUNBOOK.md)**.

> **Testing status.** The ingestion idempotency logic is covered by a unit suite (`uv run pytest`: first run
> loads all files, second run is a no-op, a changed file reloads only its table, a dropped table self-heals).
> The dbt project has 116 data tests plus Elementary monitoring. The Databricks, Google Drive and GitHub
> Actions parts need your own credentials, so expect a round of adjustment on the first run in a new workspace.

---

## 1. Headline decisions

| Decision | Why |
|---|---|
| **uv for all Python** | One `pyproject.toml` + `uv.lock` pins dbt, Elementary and the ingestion package identically on a laptop, in CI and on Databricks. `uv sync --frozen` in CI means "works on my machine" actually transfers. |
| **Idempotent by construction** | Pipelines get re-run (retries, schedules, backfills). Every stage is safe to run again: ingestion skips unchanged files via a content hash; dbt merges on keys / rebuilds deterministically. No duplicates, no drift. |
| **Separate ingestion identity** | Only the ingestion service principal can write bronze; dbt principals can only read it. "Load raw" and "transform" are different trust levels. |
| **Wide fact + report models** | Consumers (incl. an AI agent) need few joins and unambiguous numbers. Ratios live in report models computed from sums, never averaged. |
| **Three environments** | Development, CI and production. A separate staging copy adds cost without new information when there is a single raw source and CI already tests every change in isolation (reasoning in `docs/DECISIONS.md` §10). |

---

## 2. Repository layout

This project lives in the `03_dbt_project/` folder of the `CDE_Bootcamp_3` repository. GitHub only reads
workflows from the **repository root**, so the CI/CD workflows are in `.github/workflows/` at the root and
are scoped to this folder.

```
CDE_Bootcamp_3/
├── .github/workflows/                            # dbt-ci · dbt-deploy-production · dbt-cleanup-ci · dbt-reusable
└── 03_dbt_project/
    ├── pyproject.toml / uv.lock / .python-version   # uv project (dbt, elementary, ingestion, dev tools)
    ├── src/marketing_ingest/                         # idempotent Drive → bronze loader (installable package)
    │   ├── config.py      # load config; no identifiers in code
    │   ├── drive.py       # Google Drive API (api_key for public folders, or service account)
    │   ├── warehouse.py   # Warehouse interface + SparkWarehouse (Databricks)
    │   ├── loader.py      # the idempotency logic (pure `plan()` + `run()`)
    │   └── cli.py         # Databricks entry point
    ├── config/ingestion.yaml                         # folder ids + file→table map (or a Databricks secret)
    ├── tests/test_ingestion_idempotency.py           # proves the loader is idempotent
    ├── databricks/
    │   ├── 01_unity_catalog_setup.sql                # catalogs, schemas, least-privilege grants
    │   └── notebooks/ingest_bronze.py                # Databricks notebook that runs the loader
    ├── dbt/
    │   ├── models/{staging,intermediate,marts}/ · seeds/ · macros/ · tests/
    │   └── dbt_project.yml · profiles.yml · packages.yml · .sqlfluff
    ├── scripts/generate_data_dictionary.py           # DATA_DICTIONARY.md from dbt metadata
    └── docs/
        ├── DECISIONS.md          # engineering decisions and reasoning
        ├── RUNBOOK.md            # step-by-step run on a live workspace
        ├── DATA_DICTIONARY.md    # generated from dbt metadata
        └── site/                 # committed static dbt documentation (HTML, with lineage)
```

---

## 3. uv

Everything Python is a single uv project. Run these from `03_dbt_project/`.

```bash
uv sync                      # create .venv from uv.lock (dbt, elementary, ingestion, dev tools)
uv run pytest                # ingestion idempotency tests
uv run sqlfluff lint dbt/models
cd dbt && uv run dbt build   # run dbt against your target (default: dev)
uv run ingest-bronze         # console script → the Drive→bronze loader (on a Databricks runtime)
```

CI uses `uv sync --frozen` (fails if the lock is stale) so the environment is reproducible. On Databricks the
notebook does `%pip install ../..` (the project root) and installs **only the three small ingestion
dependencies**; dbt and Elementary are a separate dependency group that never lands on the cluster.

---

## 4. Idempotency

Re-running any part of the pipeline is safe and converges to the same state.

### Ingestion (Drive → bronze) — content-hash manifest

`bronze_production._meta.ingestion_manifest` records the **MD5 of the last successful load of each source
file**. The Google Drive API returns each file's server-side MD5 *without downloading it*, so on every run
the loader decides per file:

| Situation | Action |
|---|---|
| MD5 == manifest **and** bronze table exists | **skip** (no download, no load, no write) |
| MD5 differs (file changed) | download → **atomically replace** that one table → update manifest |
| file new / not in manifest | load → record |
| manifest has it but the table was dropped | **reload** (self-heal) |

So: first run loads all 9 files; an unchanged re-run does nothing; changing one file reloads only that
table. `CREATE OR REPLACE TABLE` is atomic in Delta/UC (readers see old or new, never partial). The
decision is a pure function (`loader.plan`) covered by tests in `tests/test_ingestion_idempotency.py`.

### Transformation (dbt) — deterministic rebuilds

- **Views / tables** (`staging`, `intermediate`, `dim`, `rpt_*`): `CREATE OR REPLACE` each run — inherently idempotent.
- **The fact** (`fct_marketing_ad_performance_daily`): incremental **`merge`** on `performance_key`, re-merging
  the trailing `incremental_lookback_days` (default 7) to absorb platform restatements. Merging on a stable key
  means re-running a day never duplicates rows. A full rebuild is `dbt build --full-refresh`.

End to end: **ingest → dbt** can be re-run any number of times and the gold tables are identical.

---

## 5. Moving data from Google Drive to Databricks

The folders are shared **"Anyone with the link"**, so the loader uses a Drive **API key** (restricted to the
Drive API) — enough to read public files *and* their MD5. (Set `auth_mode: service_account` for private folders.)

**One-time setup**
1. Run `databricks/01_unity_catalog_setup.sql` (creates catalogs/schemas/volume/`_meta` and grants).
2. Create a Drive API key (Google Cloud → enable Drive API → create API key, restrict to Drive API).
3. Store it as a Databricks secret: `databricks secrets put-secret gdrive api_key`.
4. Check `config/ingestion.yaml` (folder links are pre-filled). To keep links out of git, put the same YAML in
   a secret `gdrive/ingestion_config` and run with `config_source="secret"`.

**Run it** (Databricks notebook or job task — needs `spark`/`dbutils`):
```python
from marketing_ingest.cli import main
main(config_path="config/ingestion.yaml")   # idempotent; skips unchanged files
```
`databricks/notebooks/ingest_bronze.py` does this. Schedule it as a **Databricks Job** before the dbt
production run. The job identity should be the **ingestion** service principal from the grants script (the
only identity allowed to write bronze).

> Why on Databricks and not GitHub Actions: the loader writes Unity Catalog tables and the landing volume,
> which requires a Databricks runtime (`spark`/`dbutils`). GitHub Actions runs the *transformation* (dbt).

---

## 6. Data model

**Grain & keys**

| Model | Grain | Key |
|---|---|---|
| `stg_facebook_ads__ad_stats` | FB ad × day | (ad_id, report_date) |
| `stg_snapchat_ads__ad_stats` | SC ad × day × country | (ad_id, report_date, country_code) |
| `int_marketing_ads` | platform × ad × day × country | `performance_key` |
| **`fct_marketing_ad_performance_daily`** | platform × ad × day × country | `performance_key` |
| `dim_marketing_ads` | platform × ad | `ad_key` |
| `rpt_marketing_campaign_daily` | day × platform × campaign × currency | those 4 |
| `rpt_marketing_platform_monthly` | month × platform | (report_month, platform) |

Platform differences handled in staging/intermediate: Snapchat's `ad_detail_id` → `ad_id`; UUID vs numeric ids
kept as **strings**; Facebook has no country → `UNSPECIFIED`; no Snapchat account/status → NULL + documented;
the text `'null'` in clicks/impressions → real NULL (**unknown ≠ zero**); Snapchat ad-group history reduced to
the latest version (prevents fan-out). Mixed currencies (FB EUR+USD, SC EUR) → native `spend` + `currency_code`
plus `spend_eur` via the `fx_rates_to_eur` seed (USD rate is a **placeholder** to replace).

**Materializations (why):** staging = view (cheap renames, always fresh); per-platform intermediate = ephemeral;
`int_marketing_ads` = view (several consumers); fact = incremental merge (big, append-mostly, restated);
dim/report = table (small, read constantly); FX = seed.

**Metrics:** CTR = clicks/impressions, CPC = spend/clicks, CPM = spend/impressions×1000 — computed in the report
models **from sums over rows where inputs were reported**, NULL (not 0) when the denominator is 0, never averaged.

---

## 7. Data quality, freshness, docs, observability

- **116 dbt tests**: uniqueness/`not_null` on keys, both stats grains; `accepted_range`
  (spend/impressions/clicks ≥ 0), `clicks ≤ impressions`, CTR ∈ [0,1]; `accepted_values` for platform & status;
  `relationships` across the chain; a currency must exist in the FX seed; **reconciliation** tests
  (fact ↔ staging, reports ↔ fact); future-date and missing-metric guards.
- **Source freshness:** both sources set `loaded_at_field: _loaded_at`, `meta.owner`, `enabled: true` and a
  2-day `warn_after`; run `dbt source freshness`. The production workflow runs it on every deploy.
- **Docs & lineage:** every source/model/key column described; `cd dbt && uv run dbt docs generate --static` → one HTML file.
  A copy is committed in `docs/site/`.
- **Data dictionary:** `docs/DATA_DICTIONARY.md`, generated from dbt metadata (`scripts/generate_data_dictionary.py`) so it can't drift.
- **Elementary:** run/test results, volume anomalies and schema changes; `edr report` → HTML (CI uploads it).

---

## 8. Environments, authentication, permissions

**Three environments** — development, CI and production.

**5 catalogs:** `bronze_production`, `silver_production`, `gold_production`, `ci_development`, `dev_sandbox`.
**Named schemas:** bronze → `landing`, `facebook_ads`, `snapchat_ads`, `_meta`; silver → `staging`,
`preparation`, `reference`, `elementary`; gold → `marketing`. CI/dev use one disposable schema each
(`PR_<n>` / `dbt_<name>`).

| Environment | dbt target | Auth | Writes to |
|---|---|---|---|
| Development | `dev` | personal access token (only here) | `dev_sandbox.dbt_<name>` |
| CI | `ci` | service principal (OAuth) | `ci_development.PR_<n>` (dropped on PR close) |
| Production | `production` | **service principal** | `silver_production.*`, `gold_production.*` |
| (ingestion) | — | **service principal** | `bronze_production.*` (only writer of bronze) |

**Production never uses a PAT.** `profiles.yml` uses `auth_type: oauth` with client id/secret from GitHub
*environment* secrets (restrict `production` to `main`). Least-privilege grants are in
`databricks/01_unity_catalog_setup.sql` — replace the placeholder IDs/email (don't copy the brief's example).
Unlike the brief's example, no principal is granted `CREATE CATALOG`: an administrator creates the catalogs once.

---

## 9. CI/CD

```
feature branch → pull request → CI (parse + sqlfluff, then slim dbt build into ci_development.PR_<n> as the CI SP,
                 deferring to prod; docs generated) → review + merge
              → Deploy to Production (push to main · daily 06:00 UTC · manual):
                 dbt build as the production SP → docs → source freshness → publish manifest → Elementary report
```
All environments call one reusable job (`dbt-reusable.yml`); the PR schema is dropped on close. Branch-protect
`main` on the CI `build` check. Workflows only run when files in `03_dbt_project/` change. Principles
demonstrated: version control, PRs, automated validation, environment separation, production deployment,
secure (service-principal) auth.

---

## 10. First-time setup

> **Full step-by-step for a live Databricks run: [`docs/RUNBOOK.md`](docs/RUNBOOK.md).**

```bash
# development environment (from 03_dbt_project/)
uv sync
cp .env.template .env        # fill host / http-path / PAT / dev catalog + schema
set -a; source .env; set +a
cd dbt && uv run dbt deps && uv run dbt debug
```
Then: run the grants SQL (fill placeholders) → create the Drive API-key secret → run the ingestion notebook →
create GitHub environments `ci` and `production` with the four Databricks secrets each → first
**Deploy to Production** run → replace the placeholder USD→EUR rate in `dbt/seeds/fx_rates_to_eur.csv`.

---

## 11. Business questions the model answers

Total spend; spend by platform / campaign; impressions per platform; most impressions / clicks by campaign;
clicks per campaign; which platform got more clicks; CTR / CPC / CPM with zero-denominator handling — all from
`rpt_marketing_campaign_daily` and `rpt_marketing_platform_monthly`. Spend is comparable across platforms via
`spend_eur`. An AI agent can answer "how much did we spend on Facebook last month?" because names are
unambiguous, every column documents its units/NULL meaning, ratios are pre-computed correctly, and tests guard
the numbers.

---

## 12. Requirements coverage (brief's Definition of Done)

Data loaded into Databricks (idempotent Drive loader) · raw in Unity Catalog · dbt connects · staging +
intermediate + unified fact · grain defined · data-quality tests · column/model docs · static HTML docs ·
lineage · Elementary · CI + development + production environments · production via service principal ·
Unity Catalog permissions · appropriate materializations · CI/CD · README · engineering decisions documented ·
answers the business questions.

## 13. Assumptions & limits

USD→EUR is a placeholder rate. FB dimension files carry one row per id (no history → no SCD2). The fact re-merges
the trailing 7 days; older restatements/deletes need `--full-refresh`. Because ingestion skips unchanged files,
source freshness measures "has new data arrived", so the static sample files will warn two days after the first
load. Snapchat sample = 2024, Facebook = 2025, so there is no shared month in the sample data.
