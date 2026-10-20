-- Grain: one row per platform x ad x report date x country.
--
-- Single place where Facebook and Snapchat are mapped onto one schema: shared column names,
-- platform-scoped surrogate keys, an explicit country for platforms that have none, and
-- spend converted to the EUR reporting currency.
--
-- Materialized as a view: it has several downstream consumers (fact, dimension) that each
-- persist their own result, so storing it a third time would add cost and no speed.
{{ config(materialized='view') }}

with unioned as (

    select * from {{ ref('int_facebook_ads__performance') }}
    union all
    select * from {{ ref('int_snapchat_ads__performance') }}

),

normalized as (

    select
        platform,
        source_ad_id,
        report_date,
        -- Facebook has no country split; make that explicit instead of leaving a NULL key part.
        coalesce(country_code, 'UNSPECIFIED') as country_code,
        source_account_id,
        account_name,
        currency_code,
        source_campaign_id,
        campaign_name,
        source_ad_group_id,
        ad_group_name,
        ad_name,
        ad_status,
        spend,
        impressions,
        clicks
    from unioned

),

fx as (

    select
        currency_code,
        rate_to_eur
    from {{ ref('fx_rates_to_eur') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['normalized.platform', 'normalized.source_ad_id', 'normalized.report_date', 'normalized.country_code']) }} as performance_key,
    {{ dbt_utils.generate_surrogate_key(['normalized.platform', 'normalized.source_ad_id']) }} as ad_key,
    {{ dbt_utils.generate_surrogate_key(['normalized.platform', 'normalized.source_campaign_id']) }} as campaign_key,
    normalized.platform,
    normalized.report_date,
    normalized.country_code,
    normalized.source_ad_id,
    normalized.ad_name,
    normalized.ad_status,
    normalized.source_ad_group_id,
    normalized.ad_group_name,
    normalized.source_campaign_id,
    normalized.campaign_name,
    normalized.source_account_id,
    normalized.account_name,
    normalized.currency_code,
    normalized.spend,
    cast(normalized.spend * fx.rate_to_eur as decimal(18, 6)) as spend_eur,
    normalized.impressions,
    normalized.clicks
from normalized
left join fx on normalized.currency_code = fx.currency_code
