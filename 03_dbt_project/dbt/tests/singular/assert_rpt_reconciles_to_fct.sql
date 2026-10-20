-- Reconciliation: both report models must add up to the fact. Returns a row per report model
-- whose totals differ from fct_marketing_ad_performance_daily.
with fct as (

    select
        sum(spend_eur) as spend_eur,
        sum(coalesce(impressions, 0)) as impressions,
        sum(coalesce(clicks, 0)) as clicks
    from {{ ref('fct_marketing_ad_performance_daily') }}

),

campaign_daily as (

    select
        'rpt_marketing_campaign_daily' as model_name,
        sum(spend_eur) as spend_eur,
        sum(coalesce(impressions, 0)) as impressions,
        sum(coalesce(clicks, 0)) as clicks
    from {{ ref('rpt_marketing_campaign_daily') }}

),

platform_monthly as (

    select
        'rpt_marketing_platform_monthly' as model_name,
        sum(spend_eur) as spend_eur,
        sum(coalesce(impressions, 0)) as impressions,
        sum(coalesce(clicks, 0)) as clicks
    from {{ ref('rpt_marketing_platform_monthly') }}

),

reports as (

    select * from campaign_daily
    union all
    select * from platform_monthly

)

select
    reports.model_name,
    reports.spend_eur as report_spend_eur,
    fct.spend_eur as fct_spend_eur
from reports
cross join fct
where abs(reports.spend_eur - fct.spend_eur) > 0.01
    or reports.impressions != fct.impressions
    or reports.clicks != fct.clicks
