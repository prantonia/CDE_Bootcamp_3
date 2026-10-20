{#-
    Catalog routing.

    production           : <custom database>_<target>   e.g. silver_production, gold_production
    dev / ci            : the target's own catalog (dev_sandbox / ci_development)

    dbt_project.yml sets +database to "silver" or "gold" per layer; this macro appends the
    environment. Developers and CI therefore never write to the shared silver/gold catalogs.
-#}
{% macro generate_database_name(custom_database_name=none, node=none) -%}
    {%- if target.name in ['production'] and custom_database_name is not none -%}
        {{ custom_database_name | trim }}_{{ target.name }}
    {%- else -%}
        {{ target.database }}
    {%- endif -%}
{%- endmacro %}
