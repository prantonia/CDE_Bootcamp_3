{#-
    Division that returns NULL (not an error, not 0) when the denominator is NULL or 0.

    NULL is the honest answer for "CTR with zero impressions" or "CPC with zero clicks":
    the metric is undefined, and a 0 would drag averages and mislead BI tools / AI agents.
-#}
{% macro safe_divide(numerator, denominator) -%}
    case
        when ({{ denominator }}) is null or ({{ denominator }}) = 0 then null
        else ({{ numerator }}) * 1.0 / ({{ denominator }})
    end
{%- endmacro %}
