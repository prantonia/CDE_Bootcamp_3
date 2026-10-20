"""
Idempotent Drive -> bronze loader.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

from .config import Config, FileSpec
from .drive import DriveClient, DriveFile
from .warehouse import ManifestEntry, Warehouse


@dataclass(frozen=True)
class Action:
    spec: FileSpec
    drive_file: DriveFile
    reason: str          # "new" | "changed" | "table-missing" | "skip-unchanged"

    @property
    def should_load(self) -> bool:
        return self.reason != "skip-unchanged"


def plan(
    specs: list[FileSpec],
    drive_by_name: dict[str, DriveFile],
    manifest_md5: dict[str, str],
    table_exists: dict[str, bool],
) -> list[Action]:
    """Decide, per expected file, whether to load or skip. Pure: no IO."""
    missing = [s.file_name for s in specs if s.file_name not in drive_by_name]
    if missing:
        raise FileNotFoundError(
            f"Expected files not found in Drive: {missing}. Present: {sorted(drive_by_name)}"
        )
    actions = []
    for spec in specs:
        df = drive_by_name[spec.file_name]
        prev = manifest_md5.get(spec.file_name)
        if prev is None:
            reason = "new"
        elif df.md5 is not None and df.md5 != prev:
            reason = "changed"
        elif not table_exists.get(spec.fqn_suffix, False):
            reason = "table-missing"     # manifest says loaded, but table was dropped: reload to self-heal
        else:
            reason = "skip-unchanged"
        actions.append(Action(spec=spec, drive_file=df, reason=reason))
    return actions


def run(cfg: Config, drive: DriveClient, warehouse: Warehouse, run_id: str, log=print) -> dict:
    """Execute one idempotent ingestion pass. Returns a summary dict."""
    warehouse.ensure_manifest()
    manifest_md5 = warehouse.read_manifest()

    # List each folder once; resolve the expected files by exact name.
    drive_by_name: dict[str, DriveFile] = {}
    for source, folder_id in cfg.folders.items():
        wanted = {s.file_name for s in cfg.files_for(source)}
        for f in drive.list_folder(folder_id):
            if f.name in wanted:
                # If a name appears twice, keep the one with an MD5 (an uploaded file, not a Google-native doc).
                if f.name not in drive_by_name or (f.md5 and not drive_by_name[f.name].md5):
                    drive_by_name[f.name] = f

    table_exists = {s.fqn_suffix: warehouse.table_exists(s.schema, s.table) for s in cfg.files}
    actions = plan(list(cfg.files), drive_by_name, manifest_md5, table_exists)

    loaded, skipped = [], []
    for action in actions:
        spec, df = action.spec, action.drive_file
        if not action.should_load:
            skipped.append(spec.file_name)
            log(f"skip   {spec.source}/{spec.file_name}  (unchanged, md5={_short(df.md5)})")
            continue

        dest_dir = f"{cfg.volume_root}/{spec.source}"
        os.makedirs(dest_dir, exist_ok=True)
        dest = f"{dest_dir}/{spec.file_name}"
        drive.download(df, dest)

        rows = warehouse.replace_table_from_file(spec.schema, spec.table, dest)
        warehouse.record_manifest(ManifestEntry(
            source=spec.source, file_name=spec.file_name, drive_file_id=df.id,
            md5=df.md5 or "", size_bytes=df.size, target_table=spec.fqn_suffix,
            row_count=rows, run_id=run_id,
        ))
        loaded.append(spec.file_name)
        log(f"load   {spec.source}/{spec.file_name} -> {cfg.catalog}.{spec.fqn_suffix}  ({rows:,} rows, {action.reason})")

    log(f"\nDone. loaded={len(loaded)} skipped={len(skipped)} total={len(actions)}  run_id={run_id}")
    return {"loaded": loaded, "skipped": skipped, "run_id": run_id}


def _short(md5: str | None) -> str:
    return (md5 or "none")[:8]
