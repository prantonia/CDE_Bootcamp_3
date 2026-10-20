-- Grain: one row per calendar month x platform.
--
-- Headline cross-platform comparison ("Compare Facebook and Snapchat spend"). Platforms bill in
-- different currencies, so money is expressed in EUR only; native-currency spend is not additive
-- across accounts and is therefore not exposed here (use rpt_marketing_campaign_daily for that).
with fct as (

    select * from {{ ref('fct_marketing_ad_performance_daily') }}

),

monthly as (

    select
        cast({{ dbt.date_trunc('month', 'report_date') }} as date) as report_month,
        platform,
        count(distinct source_campaign_id) as active_campaigns,
        count(distinct ad_key) as active_ads,
        sum(spend_eur) as spend_eur,
        sum(impressions) as impressions,
        sum(clicks) as clicks,
        sum(case when clicks is not null then spend_eur end) as spend_eur_where_clicks_reported,
        sum(case when impressions is not null then spend_eur end) as spend_eur_where_impressions_reported,
        sum(case when clicks is not null and impressions is not null then clicks end) as clicks_where_both_reported,
        sum(case when clicks is not null and impressions is not null then impressions end) as impressions_where_both_reported
    from fct
    group by 1, 2

)

select
    *,
    round({{ safe_divide('clicks_where_both_reported', 'impressions_where_both_reported') }}, 6) as ctr,
    round({{ safe_divide('spend_eur_where_clicks_reported', 'clicks') }}, 6) as cpc_eur,
    round({{ safe_divide('spend_eur_where_impressions_reported * 1000', 'impressions') }}, 6) as cpm_eur
from monthly
