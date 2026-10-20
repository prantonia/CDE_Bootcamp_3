-- Grain: one row per platform x ad x report date x country.
--
-- Incremental (merge on performance_key) because:
--   * history is append-mostly: a new day arrives per platform per run;
--   * platforms restate the most recent days, so we re-merge a lookback window rather than
--     only appending - this keeps corrections without rebuilding years of history;
--   * a full rebuild stays available with `dbt build --full-refresh` (e.g. after a logic change
--     or a restatement older than the lookback window).
-- Rows deleted at the source are not removed by a merge; a full refresh clears them.
{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='performance_key',
        on_schema_change='append_new_columns',
        file_format='delta'
    )
}}

select
    performance_key,
    ad_key,
    campaign_key,
    platform,
    report_date,
    country_code,
    source_ad_id,
    ad_name,
    ad_status,
    source_ad_group_id,
    ad_group_name,
    source_campaign_id,
    campaign_name,
    source_account_id,
    account_name,
    currency_code,
    spend,
    spend_eur,
    impressions,
    clicks
from {{ ref('int_marketing_ads') }}

{% if is_incremental() %}
where report_date >= {{ dbt.dateadd('day', -1 * var('incremental_lookback_days'), '(select max(report_date) from ' ~ this ~ ')') }}  -- noqa: LT02
{% endif %}
