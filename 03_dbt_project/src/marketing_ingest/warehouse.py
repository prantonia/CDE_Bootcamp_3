"""
Warehouse operations behind a small interface.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class ManifestEntry:
    source: str
    file_name: str
    drive_file_id: str
    md5: str
    size_bytes: int | None
    target_table: str
    row_count: int
    run_id: str


class Warehouse(Protocol):
    def ensure_manifest(self) -> None: ...
    def read_manifest(self) -> dict[str, str]: ...          # file_name -> md5 of last successful load
    def table_exists(self, schema: str, table: str) -> bool: ...
    def replace_table_from_file(self, schema: str, table: str, file_path: str) -> int: ...  # returns row count
    def record_manifest(self, entry: ManifestEntry) -> None: ...


class SparkWarehouse:
    """Databricks / Unity Catalog implementation."""

    def __init__(self, spark, catalog: str, meta_schema: str, manifest_table: str):
        self._spark = spark
        self._catalog = catalog
        self._meta_schema = meta_schema
        self._manifest = f"{catalog}.{meta_schema}.{manifest_table}"

    def ensure_manifest(self) -> None:
        self._spark.sql(f"CREATE SCHEMA IF NOT EXISTS {self._catalog}.{self._meta_schema}")
        self._spark.sql(f"""
            CREATE TABLE IF NOT EXISTS {self._manifest} (
                source         STRING,
                file_name      STRING,
                drive_file_id  STRING,
                md5            STRING,
                size_bytes     BIGINT,
                target_table   STRING,
                row_count      BIGINT,
                run_id         STRING,
                loaded_at      TIMESTAMP
            ) USING DELTA
        """)

    def read_manifest(self) -> dict[str, str]:
        rows = self._spark.sql(f"SELECT file_name, md5 FROM {self._manifest}").collect()
        return {r["file_name"]: r["md5"] for r in rows}

    def table_exists(self, schema: str, table: str) -> bool:
        return self._spark.catalog.tableExists(f"{self._catalog}.{schema}.{table}")

    def replace_table_from_file(self, schema: str, table: str, file_path: str) -> int:
        fqn = f"{self._catalog}.{schema}.{table}"
        self._spark.sql(f"CREATE SCHEMA IF NOT EXISTS {self._catalog}.{schema}")
        # Atomic in Delta/UC: readers see either the old or the new table, never a partial one.
        # Raw layer keeps every column a STRING; typing happens in dbt staging.
        self._spark.sql(f"""
            CREATE OR REPLACE TABLE {fqn} AS
            SELECT *, current_timestamp() AS _loaded_at
            FROM read_files('{file_path}', format => 'csv', header => true, inferColumnTypes => false)
        """)
        return self._spark.table(fqn).count()

    def record_manifest(self, entry: ManifestEntry) -> None:
        # MERGE keyed on (source, file_name) keeps exactly one current row per source file.
        self._spark.sql(f"""
            MERGE INTO {self._manifest} AS t
            USING (SELECT
                '{entry.source}'   AS source,
                '{entry.file_name}' AS file_name,
                '{entry.drive_file_id}' AS drive_file_id,
                '{entry.md5}'      AS md5,
                CAST({entry.size_bytes if entry.size_bytes is not None else 'NULL'} AS BIGINT) AS size_bytes,
                '{entry.target_table}' AS target_table,
                CAST({entry.row_count} AS BIGINT) AS row_count,
                '{entry.run_id}'   AS run_id,
                current_timestamp() AS loaded_at
            ) AS s
            ON t.source = s.source AND t.file_name = s.file_name
            WHEN MATCHED THEN UPDATE SET *
            WHEN NOT MATCHED THEN INSERT *
        """)
