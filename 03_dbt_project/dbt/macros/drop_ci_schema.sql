{#-
    Drops a pull-request schema in the CI catalog. Called by the cleanup workflow when a PR closes:

        dbt run-operation drop_ci_schema --args '{schema_name: PR_123}' --target ci

    Guard rails: only runs on the `ci` target and only for schemas starting with PR_, so it can
    never touch production or a developer's sandbox.
-#}
{% macro drop_ci_schema(schema_name) %}
    {% if target.name != 'ci' %}
        {{ exceptions.raise_compiler_error("drop_ci_schema only runs on the ci target (current: " ~ target.name ~ ")") }}
    {% endif %}
    {% if not (schema_name | upper).startswith('PR_') %}
        {{ exceptions.raise_compiler_error("Refusing to drop schema '" ~ schema_name ~ "': name must start with PR_") }}
    {% endif %}
    {% do run_query('drop schema if exists ' ~ target.database ~ '.' ~ schema_name ~ ' cascade') %}
    {{ log('Dropped schema ' ~ target.database ~ '.' ~ schema_name, info=True) }}
{% endmacro %}
