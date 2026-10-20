"""
Ingestion configuration.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass

import yaml

_FOLDER_ID_RE = re.compile(r"/folders/([A-Za-z0-9_-]+)")


@dataclass(frozen=True)
class FileSpec:
    """One source file and the bronze table it lands in."""

    source: str          # "facebook" / "snapchat"
    file_name: str       # exact Drive file name
    schema: str          # bronze schema, e.g. "facebook_ads"
    table: str           # bronze table, e.g. "ad_stats"

    @property
    def fqn_suffix(self) -> str:
        return f"{self.schema}.{self.table}"


@dataclass(frozen=True)
class Config:
    catalog: str
    volume_root: str
    meta_schema: str
    manifest_table: str
    auth_mode: str                     # "api_key" (public folders) | "service_account"
    secret_scope: str
    folders: dict[str, str]            # source -> Drive folder id
    files: tuple[FileSpec, ...]

    @property
    def manifest_fqn(self) -> str:
        return f"{self.catalog}.{self.meta_schema}.{self.manifest_table}"

    def files_for(self, source: str) -> list[FileSpec]:
        return [f for f in self.files if f.source == source]


def _folder_id(value: str) -> str:
    """Accept either a bare folder id or a full Drive folder URL."""
    match = _FOLDER_ID_RE.search(value)
    return match.group(1) if match else value.strip()


def from_dict(raw: dict) -> Config:
    files = tuple(
        FileSpec(source=f["source"], file_name=f["file_name"], schema=f["schema"], table=f["table"])
        for f in raw["files"]
    )
    folders = {src: _folder_id(val) for src, val in raw["folders"].items()}
    return Config(
        catalog=raw["catalog"],
        volume_root=raw["volume_root"].rstrip("/"),
        meta_schema=raw.get("meta_schema", "_meta"),
        manifest_table=raw.get("manifest_table", "ingestion_manifest"),
        auth_mode=raw.get("auth_mode", "api_key"),
        secret_scope=raw.get("secret_scope", "gdrive"),
        folders=folders,
        files=files,
    )


def load(path: str) -> Config:
    """Load config from a YAML (or JSON) file."""
    with open(path) as fh:
        text = fh.read()
    raw = yaml.safe_load(text) if not text.lstrip().startswith("{") else json.loads(text)
    return from_dict(raw)


def load_from_string(text: str) -> Config:
    """Load config from a JSON/YAML string (e.g. a Databricks secret)."""
    return from_dict(yaml.safe_load(text))
