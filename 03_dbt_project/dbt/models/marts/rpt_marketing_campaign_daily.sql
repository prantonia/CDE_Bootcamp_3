-- Grain: one row per report date x platform x campaign x currency.
--
-- The model analysts, BI tools and AI agents should use for campaign questions. Ratio metrics
-- (CTR, CPC, CPM) are computed here from SUMS, never averaged, and only over rows where the
-- inputs were actually reported (Facebook reports no clicks on ~26% of rows). The "_where_"
-- columns are the additive building blocks, so any further roll-up can recompute the ratios
-- correctly instead of averaging them.
with fct as (

    select * from {{ ref('fct_marketing_ad_performance_daily') }}

),

daily as (

    select
        report_date,
        platform,
        campaign_key,
        source_campaign_id,
        campaign_name,
        currency_code,
        count(distinct ad_key) as active_ads,
        sum(spend) as spend,
        sum(spend_eur) as spend_eur,
        sum(impressions) as impressions,
        sum(clicks) as clicks,
        sum(case when clicks is not null then spend end) as spend_where_clicks_reported,
        sum(case when clicks is not null then spend_eur end) as spend_eur_where_clicks_reported,
        sum(case when impressions is not null then spend end) as spend_where_impressions_reported,
        sum(case when impressions is not null then spend_eur end) as spend_eur_where_impressions_reported,
        sum(case when clicks is not null and impressions is not null then clicks end) as clicks_where_both_reported,
        sum(case when clicks is not null and impressions is not null then impressions end) as impressions_where_both_reported
    from fct
    group by report_date, platform, campaign_key, source_campaign_id, campaign_name, currency_code

)

select
    *,
    round({{ safe_divide('clicks_where_both_reported', 'impressions_where_both_reported') }}, 6) as ctr,
    round({{ safe_divide('spend_where_clicks_reported', 'clicks') }}, 6) as cpc,
    round({{ safe_divide('spend_eur_where_clicks_reported', 'clicks') }}, 6) as cpc_eur,
    round({{ safe_divide('spend_where_impressions_reported * 1000', 'impressions') }}, 6) as cpm,
    round({{ safe_divide('spend_eur_where_impressions_reported * 1000', 'impressions') }}, 6) as cpm_eur
from daily
