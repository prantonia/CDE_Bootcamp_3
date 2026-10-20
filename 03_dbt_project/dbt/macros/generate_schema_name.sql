{#-
    Schema routing.

    production           : the custom schema exactly as configured (staging, preparation, marketing, ...)
    dev / ci            : the target's single schema (dbt_<name> or PR_<number>), so one developer or
                           one pull request owns one disposable schema that is trivial to drop.
-#}
{% macro generate_schema_name(custom_schema_name=none, node=none) -%}
    {%- if target.name in ['production'] and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
