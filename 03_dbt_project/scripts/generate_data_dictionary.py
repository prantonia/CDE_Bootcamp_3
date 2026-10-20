#!/usr/bin/env python3
"""Generate docs/DATA_DICTIONARY.md from dbt's manifest.json + catalog.json.

The dictionary is built from the same descriptions that dbt docs shows, so it cannot drift from the
models: change a description in a .yml file, regenerate, done.

    cd marketing_platform
    dbt docs generate          # writes target/manifest.json and target/catalog.json
    python ../scripts/generate_data_dictionary.py
"""
import json
import sys
from pathlib import Path

TARGET = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("target")
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("../docs/DATA_DICTIONARY.md")

manifest = json.loads((TARGET / "manifest.json").read_text())
catalog = json.loads((TARGET / "catalog.json").read_text())
cat_nodes = {**catalog.get("nodes", {}), **catalog.get("sources", {})}

LAYERS = [
    ("Marts (gold): the tables analysts, BI tools and AI agents should query", "marts"),
    ("Intermediate (silver)", "intermediate"),
    ("Staging (silver)", "staging"),
    ("Reference data (seed)", "seeds"),
]


def layer_of(node):
    path = node["original_file_path"]
    if node["resource_type"] == "seed":
        return "seeds"
    return path.split("/")[1] if path.startswith("models/") else "other"


def cell(text):
    return (text or "").replace("\n", " ").replace("|", "\\|").strip()


def tests_for(unique_id):
    found = {}
    for n in manifest["nodes"].values():
        if n["resource_type"] == "test" and unique_id in n.get("depends_on", {}).get("nodes", []):
            col = n.get("column_name")
            if col:
                found.setdefault(col, []).append(n["test_metadata"]["name"] if n.get("test_metadata") else n["name"])
    return found


def render_model(node):
    cols = node.get("columns", {})
    cat_cols = cat_nodes.get(node["unique_id"], {}).get("columns", {})
    tested = tests_for(node["unique_id"])
    lines = [f"### `{node['name']}`", "", cell(node["description"]), ""]
    if node["resource_type"] == "model":
        lines += [f"*Materialization:* `{node['config'].get('materialized')}`", ""]
    # catalog columns give the real order and warehouse types; YAML gives descriptions
    ordered = sorted(cat_cols.values(), key=lambda c: c["index"]) if cat_cols else [{"name": k, "type": ""} for k in cols]
    lines += ["| Column | Type | Description | Tests |", "|---|---|---|---|"]
    for c in ordered:
        name = c["name"]
        meta = cols.get(name) or cols.get(name.lower()) or {}
        tests = ", ".join(sorted(set(tested.get(name, []))))
        lines.append(f"| `{name}` | {cell(c.get('type', '')).lower()} | {cell(meta.get('description'))} | {tests} |")
    return lines + [""]


out = [
    "# Data dictionary",
    "",
    "Generated from the dbt project (`scripts/generate_data_dictionary.py`). Do not edit by hand: change the",
    "description in the model's `.yml` file and regenerate. Column types are those of the warehouse the docs",
    "were generated against.",
    "",
    "**Conventions.** NULL in `clicks` / `impressions` means *not reported* (unknown), not zero. `spend` is in the",
    "account currency (`currency_code`); `spend_eur` is comparable across platforms. `country_code = 'UNSPECIFIED'`",
    "means the platform gives no country breakdown (all Facebook rows). Ratio metrics (CTR, CPC, CPM) must be",
    "recomputed from sums, never averaged.",
    "",
]
nodes = [n for n in manifest["nodes"].values()
         if n["package_name"] == "marketing_platform" and n["resource_type"] in ("model", "seed")]
for title, key in LAYERS:
    group = sorted((n for n in nodes if layer_of(n) == key), key=lambda n: n["name"])
    if not group:
        continue
    out += [f"## {title}", ""]
    for n in group:
        out += render_model(n)

out += ["## Raw sources (bronze)", "", "All raw columns are strings; typing happens in staging.", ""]
for s in sorted(manifest["sources"].values(), key=lambda s: (s["source_name"], s["name"])):
    out += [f"### `{s['source_name']}.{s['name']}`", "", cell(s["description"]), ""]
    if s.get("columns"):
        out += ["| Column | Description |", "|---|---|"]
        out += [f"| `{c}` | {cell(v.get('description'))} |" for c, v in s["columns"].items()]
        out.append("")

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("\n".join(out))
print(f"wrote {OUT} ({len(nodes)} models/seeds, {len(manifest['sources'])} sources)")
