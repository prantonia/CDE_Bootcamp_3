"""Entry point for the idempotent Drive -> bronze ingestion.

Runs on a Databricks runtime, where `spark` and `dbutils` are provided. Use it from a Databricks
notebook / job task:

    from marketing_ingest.cli import main
    main(config_path="config/ingestion.yaml")

or as the console script `ingest-bronze` on a cluster that has `spark`/`dbutils` in scope.
Config can also come from a Databricks secret (set config_source="secret").
"""
from __future__ import annotations

import os
import uuid

from . import config as config_mod
from .drive import DriveClient
from .loader import run
from .warehouse import SparkWarehouse


def _get_spark():
    try:
        from databricks.sdk.runtime import spark  # modern runtimes
        return spark
    except Exception:
        import builtins
        if hasattr(builtins, "spark"):
            return builtins.spark
    raise RuntimeError("No `spark` session found. Run this on a Databricks cluster.")


def _get_dbutils():
    try:
        from databricks.sdk.runtime import dbutils
        return dbutils
    except Exception:
        import builtins
        if hasattr(builtins, "dbutils"):
            return builtins.dbutils
    return None


def main(config_path: str = "config/ingestion.yaml", config_source: str = "file") -> dict:
    spark = _get_spark()
    dbutils = _get_dbutils()

    if config_source == "secret":
        scope = os.environ.get("INGEST_SECRET_SCOPE", "gdrive")
        cfg = config_mod.load_from_string(dbutils.secrets.get(scope, "ingestion_config"))
    else:
        cfg = config_mod.load(config_path)

    def secret_getter(scope: str, key: str) -> str:
        if dbutils is None:
            raise RuntimeError("dbutils unavailable; cannot read secret for Drive auth.")
        return dbutils.secrets.get(scope, key)

    drive = DriveClient.from_config(cfg.auth_mode, cfg.secret_scope, secret_getter)
    warehouse = SparkWarehouse(spark, cfg.catalog, cfg.meta_schema, cfg.manifest_table)
    return run(cfg, drive, warehouse, run_id=str(uuid.uuid4()))


if __name__ == "__main__":
    main()
