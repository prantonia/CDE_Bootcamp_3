# Static dbt documentation

`dbt_docs.html` is a self-contained copy of the dbt documentation site: the lineage graph, every source, model
and column description, and the tests. Open it directly in a browser; no server is needed.

This committed copy was generated without a warehouse connection, so it shows structure, lineage and
descriptions but not the live column types. To regenerate it with a full catalog from Databricks:

```bash
cd 03_dbt_project/dbt
uv run dbt docs generate --static
cp target/static_index.html ../docs/site/dbt_docs.html
```

The CI and production workflows also publish a fresh copy as the `dbt-docs-<target>` run artifact on every run.
