# Databricks notebook source
# MAGIC %md
# MAGIC # Idempotent ingestion: Google Drive -> bronze
# MAGIC
# MAGIC Installs the repo's `marketing_ingest` package and runs one idempotent load. Safe to run on a
# MAGIC schedule: unchanged files are skipped via the content-hash manifest
# MAGIC (`bronze_production._meta.ingestion_manifest`).
# MAGIC
# MAGIC Prereqs: run `databricks/01_unity_catalog_setup.sql` once, and store the Drive key in a secret
# MAGIC (`gdrive/api_key` for public folders, or `gdrive/service_account_json` for private ones).

# COMMAND ----------

# A notebook's working directory is its own folder (databricks/notebooks), so the repo root,
# which holds pyproject.toml, is two levels up. Run this from inside the Databricks Git folder.
# MAGIC %pip install ../..

# COMMAND ----------

dbutils.library.restartPython()

# COMMAND ----------

from marketing_ingest.cli import main

# config_source="file" reads config/ingestion.yaml (path is relative to this notebook); use "secret" to read it from gdrive/ingestion_config.
summary = main(config_path="../../config/ingestion.yaml", config_source="file")
print(summary)

# COMMAND ----------

# MAGIC %md
# MAGIC Next step: run dbt (`uv run dbt build` locally, or the Deploy to Production workflow) to build
# MAGIC silver + gold from bronze.
