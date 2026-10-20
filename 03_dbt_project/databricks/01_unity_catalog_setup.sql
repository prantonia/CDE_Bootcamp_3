-- Unity Catalog setup: catalogs, schemas and least-privilege grants.
--
-- Three environments: CI (ci_development), development (dev_sandbox) and production (*_production).
--
-- Run once, as a metastore admin / catalog owner (a human, NOT a service principal).
--
-- Replace the placeholders before running (do NOT reuse the example IDs from the brief):
--   <SP_INGEST_APP_ID>      app id of the INGESTION service principal (Drive -> bronze loader)
--   <SP_PRODUCTION_APP_ID>  app id of the production dbt service principal
--   <SP_CI_APP_ID>          app id of the CI dbt service principal
--   <YOUR_EMAIL>            your Databricks user (e.g. you@company.com)
--   marketing_analysts      an account group of consumers (create it or rename)
--
-- Also grant each service principal "Can use" on the SQL warehouse (Compute -> SQL warehouses ->
-- Permissions) - a workspace permission, not a SQL grant.
--
-- Security model (least privilege):
--   * The INGESTION principal is the ONLY identity that can write bronze. It separates "load raw data"
--     from "transform it": the dbt principals can only SELECT bronze, so a transformation job can never
--     alter or overwrite raw data.
--   * No CREATE CATALOG on the metastore: pipelines never create catalogs; an admin does, here.

-- ---------- 1. Catalogs ------------------------------------------------------------
CREATE CATALOG IF NOT EXISTS bronze_production COMMENT 'Raw ads data exactly as extracted (all strings)';
CREATE CATALOG IF NOT EXISTS silver_production COMMENT 'Production: staging models + intermediate + elementary';
CREATE CATALOG IF NOT EXISTS gold_production   COMMENT 'Production: marketing marts consumed by analysts, BI and AI agents';
CREATE CATALOG IF NOT EXISTS ci_development    COMMENT 'CI: one disposable schema per pull request (PR_<number>)';
CREATE CATALOG IF NOT EXISTS dev_sandbox       COMMENT 'Developers: one schema per developer (dbt_<name>)';

-- ---------- 2. Bronze schemas + landing volume + ingestion metadata -----------------
CREATE SCHEMA IF NOT EXISTS bronze_production.landing      COMMENT 'Landing area for raw files';
CREATE SCHEMA IF NOT EXISTS bronze_production.facebook_ads COMMENT 'Raw Facebook Ads tables';
CREATE SCHEMA IF NOT EXISTS bronze_production.snapchat_ads COMMENT 'Raw Snapchat Ads tables';
CREATE SCHEMA IF NOT EXISTS bronze_production._meta        COMMENT 'Ingestion control tables (content-hash manifest)';
CREATE VOLUME IF NOT EXISTS bronze_production.landing.raw_files COMMENT 'Drive files are downloaded here before loading';
-- The ingestion manifest (bronze_production._meta.ingestion_manifest) is created by the loader on its
-- first run (CREATE TABLE IF NOT EXISTS). It records each source file's MD5 so re-runs skip unchanged files.

-- ---------- 3. Ingestion service principal (Drive -> bronze) -------------------------
-- The only writer of bronze. Needs write on the two bronze schemas, the _meta manifest, and the volume.
GRANT USE CATALOG ON CATALOG bronze_production TO `<SP_INGEST_APP_ID>`;
GRANT USE SCHEMA, CREATE TABLE, SELECT, MODIFY ON SCHEMA bronze_production.facebook_ads TO `<SP_INGEST_APP_ID>`;
GRANT USE SCHEMA, CREATE TABLE, SELECT, MODIFY ON SCHEMA bronze_production.snapchat_ads TO `<SP_INGEST_APP_ID>`;
GRANT USE SCHEMA, CREATE TABLE, SELECT, MODIFY ON SCHEMA bronze_production._meta        TO `<SP_INGEST_APP_ID>`;
GRANT READ VOLUME, WRITE VOLUME ON VOLUME bronze_production.landing.raw_files            TO `<SP_INGEST_APP_ID>`;

-- ---------- 4. Production dbt service principal --------------------------------------
GRANT USE CATALOG ON CATALOG bronze_production                    TO `<SP_PRODUCTION_APP_ID>`;
GRANT USE SCHEMA, SELECT ON SCHEMA bronze_production.facebook_ads TO `<SP_PRODUCTION_APP_ID>`;
GRANT USE SCHEMA, SELECT ON SCHEMA bronze_production.snapchat_ads TO `<SP_PRODUCTION_APP_ID>`;
GRANT USE CATALOG, USE SCHEMA, CREATE SCHEMA, CREATE TABLE ON CATALOG silver_production TO `<SP_PRODUCTION_APP_ID>`;
GRANT USE CATALOG, USE SCHEMA, CREATE SCHEMA, CREATE TABLE ON CATALOG gold_production   TO `<SP_PRODUCTION_APP_ID>`;

-- ---------- 5. CI dbt service principal ----------------------------------------------
GRANT USE CATALOG ON CATALOG bronze_production                    TO `<SP_CI_APP_ID>`;
GRANT USE SCHEMA, SELECT ON SCHEMA bronze_production.facebook_ads TO `<SP_CI_APP_ID>`;
GRANT USE SCHEMA, SELECT ON SCHEMA bronze_production.snapchat_ads TO `<SP_CI_APP_ID>`;
GRANT USE CATALOG, USE SCHEMA, CREATE SCHEMA, CREATE TABLE ON CATALOG ci_development TO `<SP_CI_APP_ID>`;
GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG silver_production TO `<SP_CI_APP_ID>`;
GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG gold_production   TO `<SP_CI_APP_ID>`;

-- ---------- 6. Development (you, a developer) ----------------------------------------------------
GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG ci_development TO `<YOUR_EMAIL>`;
GRANT USE CATALOG, USE SCHEMA, CREATE SCHEMA, CREATE TABLE ON CATALOG dev_sandbox TO `<YOUR_EMAIL>`;
GRANT USE CATALOG ON CATALOG bronze_production                    TO `<YOUR_EMAIL>`;
GRANT USE SCHEMA, SELECT ON SCHEMA bronze_production.facebook_ads TO `<YOUR_EMAIL>`;
GRANT USE SCHEMA, SELECT ON SCHEMA bronze_production.snapchat_ads TO `<YOUR_EMAIL>`;
-- Optional: let a developer run the ingestion manually (otherwise only the ingestion SP can)
GRANT USE SCHEMA, CREATE TABLE, SELECT, MODIFY ON SCHEMA bronze_production.facebook_ads TO `<YOUR_EMAIL>`;
GRANT USE SCHEMA, CREATE TABLE, SELECT, MODIFY ON SCHEMA bronze_production.snapchat_ads TO `<YOUR_EMAIL>`;
GRANT USE SCHEMA, CREATE TABLE, SELECT, MODIFY ON SCHEMA bronze_production._meta        TO `<YOUR_EMAIL>`;
GRANT READ VOLUME, WRITE VOLUME ON VOLUME bronze_production.landing.raw_files            TO `<YOUR_EMAIL>`;

-- ---------- 7. Consumers ------------------------------------------------------------
-- Read-only access to the finished marketing marts (covers the `marketing` schema created by the first run).
GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG gold_production TO `marketing_analysts`;
