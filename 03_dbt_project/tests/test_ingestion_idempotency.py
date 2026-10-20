"""Idempotency tests for the Drive -> bronze loader, using a fake Drive and an in-memory warehouse.

Proves: first run loads all files; an unchanged second run is a no-op (every file skipped); a changed
file reloads only that one table; a dropped table self-heals; a missing source file fails loudly.
"""
from __future__ import annotations

import csv
import hashlib

from marketing_ingest import config as config_mod
from marketing_ingest.drive import DriveFile
from marketing_ingest.loader import plan, run
from marketing_ingest.warehouse import ManifestEntry

RAW = {
    "a.csv": "id,v\n1,x\n2,y\n",
    "b.csv": "k\n1\n",
}


def _cfg(tmp_path):
    return config_mod.from_dict({
        "catalog": "bronze", "volume_root": str(tmp_path),
        "folders": {"fb": "FID"},
        "files": [
            {"source": "fb", "file_name": "a.csv", "schema": "fb_ads", "table": "stats"},
            {"source": "fb", "file_name": "b.csv", "schema": "fb_ads", "table": "dim"},
        ],
    })


class FakeDrive:
    """Serves in-memory files; md5 is a content hash so changing content changes the md5."""

    def __init__(self, contents: dict[str, str]):
        self.contents = dict(contents)

    def _md5(self, name: str) -> str:
        return hashlib.md5(self.contents[name].encode()).hexdigest()

    def list_folder(self, folder_id):
        return [DriveFile(id=f"id-{n}", name=n, md5=self._md5(n), size=len(c), mime="text/csv")
                for n, c in self.contents.items()]

    def download(self, file, dest_path):
        with open(dest_path, "w") as fh:
            fh.write(self.contents[file.name])


class MemoryWarehouse:
    """Implements the Warehouse interface with plain dicts; mirrors SparkWarehouse's behaviour."""

    def __init__(self):
        self.tables: dict[tuple[str, str], list[list[str]]] = {}
        self.manifest: dict[str, ManifestEntry] = {}
        self.load_calls = 0

    def ensure_manifest(self):
        pass

    def read_manifest(self):
        return {name: e.md5 for name, e in self.manifest.items()}

    def table_exists(self, schema, table):
        return (schema, table) in self.tables

    def replace_table_from_file(self, schema, table, file_path):
        self.load_calls += 1
        with open(file_path, newline="") as fh:
            rows = list(csv.reader(fh))[1:]       # header row dropped; every value stays a string
        self.tables[(schema, table)] = rows        # replace, never append
        return len(rows)

    def record_manifest(self, entry: ManifestEntry):
        self.manifest[entry.file_name] = entry     # one current row per source file

    def count(self, schema, table):
        return len(self.tables[(schema, table)])


def test_first_run_loads_all_then_second_run_is_noop(tmp_path):
    cfg, wh, drive = _cfg(tmp_path), MemoryWarehouse(), FakeDrive(RAW)

    r1 = run(cfg, drive, wh, run_id="run1", log=lambda *_: None)
    assert set(r1["loaded"]) == {"a.csv", "b.csv"} and r1["skipped"] == []
    assert wh.load_calls == 2
    assert wh.count("fb_ads", "stats") == 2

    r2 = run(cfg, drive, wh, run_id="run2", log=lambda *_: None)
    assert r2["loaded"] == [] and set(r2["skipped"]) == {"a.csv", "b.csv"}
    assert wh.load_calls == 2  # unchanged: no extra load


def test_changed_file_reloads_only_that_table(tmp_path):
    cfg, wh, drive = _cfg(tmp_path), MemoryWarehouse(), FakeDrive(RAW)
    run(cfg, drive, wh, run_id="run1", log=lambda *_: None)

    drive.contents["a.csv"] = "id,v\n1,x\n2,y\n3,z\n"   # a.csv changes, b.csv does not
    r = run(cfg, drive, wh, run_id="run2", log=lambda *_: None)
    assert r["loaded"] == ["a.csv"] and r["skipped"] == ["b.csv"]
    assert wh.count("fb_ads", "stats") == 3


def test_dropped_table_self_heals(tmp_path):
    cfg, wh, drive = _cfg(tmp_path), MemoryWarehouse(), FakeDrive(RAW)
    run(cfg, drive, wh, run_id="run1", log=lambda *_: None)

    del wh.tables[("fb_ads", "dim")]   # table gone but the manifest still records it
    r = run(cfg, drive, wh, run_id="run2", log=lambda *_: None)
    assert r["loaded"] == ["b.csv"] and r["skipped"] == ["a.csv"]
    assert wh.table_exists("fb_ads", "dim")


def test_plan_raises_on_missing_file(tmp_path):
    specs = list(_cfg(tmp_path).files)
    drive_by_name = {"a.csv": DriveFile("i", "a.csv", "m", 1, "text/csv")}  # b.csv missing
    try:
        plan(specs, drive_by_name, {}, {})
        assert False, "expected FileNotFoundError"
    except FileNotFoundError as e:
        assert "b.csv" in str(e)
