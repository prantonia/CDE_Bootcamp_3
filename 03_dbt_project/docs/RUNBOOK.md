# Runbook — running the real pipeline (Google Drive → Databricks → dbt)

End-to-end steps to stand the platform up on a live Databricks workspace. Why each choice was made is in [DECISIONS.md](DECISIONS.md). Follow top to bottom the
first time; after that, only **Step 7** (ingest) and **Step 8** (transform) run on a schedule.

```
Drive (public folders) ──► bronze (Unity Catalog) ──► dbt silver/gold ──► analysts · BI · AI agent
        Step 7                   Step 7                     Step 8
```


---

## Step 0 — Prerequisites 

- A Databricks workspace with **Unity Catalog** enabled and a **SQL warehouse** (or an all-purpose cluster) running.
- Permission to create **catalogs** and **service principals** (metastore admin / account admin), or someone who can.
- The **Databricks CLI** installed and configured locally: `databricks configure` (host + a PAT), and `databricks auth describe` succeeds.
- `uv` installed locally (only needed if you run dbt from your machine instead of GitHub Actions).
- The 9 source CSVs sitting in the two **public** Google Drive folders (shared "Anyone with the link").

Grab two connection values now — you'll reuse them everywhere:
- **Host**, e.g. `adb-1234567890.11.azuredatabricks.net`
- **HTTP path** of the SQL warehouse: SQL Warehouses → your warehouse → *Connection details* → `/sql/1.0/warehouses/xxxx`.

---

## Step 1 — Create service principals 

Settings → **Identity and access** → **Service principals** → *Add*. Create (at least) two:

| Name | Role in this pipeline |
|---|---|
| `sp-marketing-ingest` | writes bronze (the Drive loader) |
| `sp-marketing-prod`   | runs the production dbt build |

Optional but recommended for full environment separation: `sp-marketing-ci` (used by pull-request validation).

For each, note its **Application ID**, and create an **OAuth secret**: open the principal → *Secrets* →
*Generate secret* → copy the **Client ID (= Application ID)** and **Client Secret**. Store them somewhere
safe for Step 6.

Then give each principal **Can use** on the SQL warehouse: SQL Warehouses → your warehouse → *Permissions* →
add each service principal with **Can use**. (This is a workspace permission, not a SQL grant.)

---

## Step 2 — Create catalogs, schemas, and grants 

Open `databricks/01_unity_catalog_setup.sql`. Replace every placeholder with real values — **do not keep the
example IDs**:

- `<SP_INGEST_APP_ID>` → `sp-marketing-ingest` Application ID
- `<SP_PRODUCTION_APP_ID>` → `sp-marketing-prod` Application ID
- `<SP_CI_APP_ID>` → the CI principal's ID (or reuse the prod ID if you skipped it)
- `<YOUR_EMAIL>` → your Databricks login email
- `marketing_analysts` → an existing account group of consumers (or create one, or change the name)

Run the whole script in a **SQL editor** or notebook as a user who can create catalogs. It creates the 7
catalogs, the bronze schemas (`facebook_ads`, `snapchat_ads`, `_meta`), the landing **volume**, and all the
least-privilege grants. Re-running it is safe (`IF NOT EXISTS`).

Verify:
```sql
SHOW CATALOGS LIKE '*_production';          -- bronze/silver/gold_production present
SHOW SCHEMAS IN bronze_production;          -- facebook_ads, snapchat_ads, _meta, landing
LIST '/Volumes/bronze_production/landing/raw_files';   -- volume exists (may be empty)
```

---

## Step 3 — Store the Google Drive key as a Databricks secret 

The folders are public, so a **Drive API key** is enough.

1. Google Cloud console → create/select a project → **APIs & Services → Enable APIs → Google Drive API → Enable**.
2. **Credentials → Create credentials → API key**. Then **Restrict key → API restrictions → Google Drive API**.
3. Save it in Databricks (CLI):
   ```bash
   databricks secrets create-scope gdrive          # once
   databricks secrets put-secret   gdrive api_key   # paste the API key when prompted
   ```
(If the folders were private instead, you'd use a service account: store its JSON as `gdrive/service_account_json`
and set `auth_mode: service_account` in `config/ingestion.yaml`.)

---

## Step 4 — Put the code in the workspace 

Workspace → **Create → Git folder** → paste the repository URL (`https://github.com/prantonia/CDE_Bootcamp_3`) → create.
The project is in the `03_dbt_project/` subfolder; it contains the `marketing_ingest` package,
`config/ingestion.yaml`, and the ingestion notebook. (Working from a Git folder is what lets the notebook's
`%pip install ../..` and the `../../config/ingestion.yaml` path resolve.)

Check `config/ingestion.yaml`: the two folder links are pre-filled; `catalog`, `volume_root`, and `auth_mode:
api_key` should match what you created. Nothing secret lives in this file.

---

## Step 5 — First ingestion: Drive → bronze 

Open `03_dbt_project/databricks/notebooks/ingest_bronze.py` in the workspace, attach it to a cluster (or serverless), and
**Run all**. It will:

1. `%pip install ../..` (installs the repo root, two levels above the notebook; only the three small ingestion packages, never dbt),
2. list both Drive folders, read each file's server-side MD5,
3. download the 9 files to the landing volume,
4. create the 9 bronze tables (all columns strings + `_loaded_at`),
5. write the content-hash ledger `bronze_production._meta.ingestion_manifest`.

Expected tail of the output: `Done. loaded=9 skipped=0 total=9`.

**Idempotency check (worth doing once):** run the notebook a *second* time with no Drive changes. It should
print `loaded=0 skipped=9` and touch nothing — that's the manifest doing its job.

Verify bronze:
```sql
SELECT count(*) FROM bronze_production.facebook_ads.ad_stats;   -- 92300
SELECT count(*) FROM bronze_production.snapchat_ads.ad_stats;   --  2809
SELECT * FROM bronze_production._meta.ingestion_manifest;       -- 9 rows, md5 + row counts
```

---

## Step 6 — Configure credentials for dbt 

The dbt `production` target authenticates as the **production service principal** (OAuth — no PAT).
`dbt/profiles.yml` reads these from the environment:

| Variable | Value |
|---|---|
| `DATABRICKS_HOST` | your host (no `https://`) |
| `DATABRICKS_HTTP_PATH` | the SQL warehouse HTTP path |
| `DBX_ID_APPLICATION_ID` | `sp-marketing-prod` Client ID |
| `DBX_SECRET` | `sp-marketing-prod` Client Secret |
| `DBT_TARGET` | `production` |

You can run dbt two ways — pick one:

**6a. From GitHub Actions (the intended production path).** In the repo on GitHub: Settings → Environments →
create `production` and `ci`, and add those first four values as **secrets** in each environment (use the CI principal's credentials in `ci`).
Restrict the `production` environment to the `main` branch. Nothing to run by hand — see Step 8.

**6b. From your laptop (quickest for a first end-to-end test).**
```bash
export DATABRICKS_HOST=adb-xxxx.11.azuredatabricks.net
export DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/xxxx
export DBX_ID_APPLICATION_ID=<prod SP client id>
export DBX_SECRET=<prod SP client secret>
export DBT_TARGET=production
```

---

## Step 7 — Transform: build silver + gold with dbt 

**If you chose 6b (laptop):**
```bash
cd 03_dbt_project
uv sync                                   # installs dbt + elementary from uv.lock
cd dbt
uv run dbt deps                           # fetch dbt_utils + elementary
uv run dbt debug                          # confirms it connects as the prod SP
uv run dbt run --select elementary        # one-off: create Elementary's tables
uv run dbt build                          # staging → intermediate → marts, + all 116 tests
uv run dbt source freshness               # warns if a bronze table has not been reloaded in 2 days
uv run dbt docs generate --static         # target/static_index.html (lineage + docs)
```
A green run ends with `Done. PASS=… WARN=1 ERROR=0` (the one warning is the known Snapchat orphan ad groups).

**If you chose 6a (GitHub Actions):** you don't run dbt by hand — Step 8 does it.

Verify gold:
```sql
SELECT platform, round(sum(spend_eur),2) spend_eur, sum(clicks) clicks
FROM gold_production.marketing.rpt_marketing_platform_monthly GROUP BY platform;
```

---

## Step 8 — Automate (the steady state) 

**Ingestion → a Databricks Job.** Workflows → *Create job* → task type **Notebook** →
`03_dbt_project/databricks/notebooks/ingest_bronze.py` → **Run as** `sp-marketing-ingest` → add a schedule (e.g. daily 05:30).
Because of the manifest, a run with no new Drive files is a cheap no-op.

**Transformation → GitHub Actions** (already wired, needs the Step 6a secrets):
- open a PR → **CI** builds the changed models into `ci_development.PR_<n>`;
- merge to `main`, or the daily 06:00 UTC schedule → **Deploy to Production** builds gold and publishes docs +
  the Elementary report as run artifacts.

Order them so ingestion (05:30) finishes before the production dbt run (06:00).

---

## Step 9 — Consume

- **SQL / BI:** point at `gold_production.marketing.*` (`fct_marketing_ad_performance_daily`, the two `rpt_*`
  tables, `dim_marketing_ads`). Consumers only need the read grant from Step 2.
- **Docs:** download the `dbt-docs-production` artifact from the latest successful workflow run, or open the
  `target/static_index.html` you generated in Step 7.
- **AI agent:** give it read access to `gold_production.marketing` and the data dictionary (`docs/DATA_DICTIONARY.md`).

---


## Using the development environment

Development is where you try a change before opening a pull request. It builds into your own schema in
`dev_sandbox`, using your personal access token (the only place a token is allowed; production and CI use service
principals).

```bash
cd 03_dbt_project/dbt
export DATABRICKS_HOST=...  DATABRICKS_HTTP_PATH=...  DATABRICKS_PAT_TOKEN=...
export DEV_SCHEMA=dbt_yourname      # your own schema in dev_sandbox
uv run dbt deps && uv run dbt build      # default target is dev
```

Then check `SHOW SCHEMAS IN dev_sandbox;` for `dbt_yourname`. Drop the schema when you are done.
