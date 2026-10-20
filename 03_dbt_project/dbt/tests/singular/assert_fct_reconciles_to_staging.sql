-- Reconciliation: the fact must contain exactly what staging holds, per platform.
-- Catches join fan-out (e.g. un-deduplicated Snapchat ad groups), dropped rows, and
-- incremental/merge drift. Returns one row per platform that does not reconcile.
with fct as (

    select
        platform,
        count(*) as row_count,
        sum(spend) as spend,
        sum(coalesce(impressions, 0)) as impressions,
        sum(coalesce(clicks, 0)) as clicks
    from {{ ref('fct_marketing_ad_performance_daily') }}
    group by platform

),

stg as (

    select
        'facebook' as platform,
        count(*) as row_count,
        sum(spend) as spend,
        sum(coalesce(impressions, 0)) as impressions,
        sum(coalesce(clicks, 0)) as clicks
    from {{ ref('stg_facebook_ads__ad_stats') }}

    union all

    select
        'snapchat' as platform,
        count(*) as row_count,
        sum(spend) as spend,
        sum(coalesce(impressions, 0)) as impressions,
        sum(coalesce(clicks, 0)) as clicks
    from {{ ref('stg_snapchat_ads__ad_stats') }}

)

select
    coalesce(fct.platform, stg.platform) as platform,
    fct.row_count as fct_rows,
    stg.row_count as stg_rows,
    fct.spend as fct_spend,
    stg.spend as stg_spend
from fct
full outer join stg on fct.platform = stg.platform
where fct.platform is null
    or stg.platform is null
    or fct.row_count != stg.row_count
    or abs(fct.spend - stg.spend) > 0.01
    or fct.impressions != stg.impressions
    or fct.clicks != stg.clicks
