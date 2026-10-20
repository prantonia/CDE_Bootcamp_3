{{ config(severity='warn') }}

-- Early-warning signal, not a hard stop: if far more rows than usual arrive without clicks or
-- impressions, CTR/CPC/CPM are being computed on a thinner sample. The baseline in the sample data
-- is ~26% missing clicks on Facebook and ~4% on Snapchat; 40% leaves headroom before alerting.
select
    platform,
    avg(case when clicks is null then 1.0 else 0.0 end) as share_missing_clicks,
    avg(case when impressions is null then 1.0 else 0.0 end) as share_missing_impressions
from {{ ref('fct_marketing_ad_performance_daily') }}
group by platform
having avg(case when clicks is null then 1.0 else 0.0 end) > 0.40
    or avg(case when impressions is null then 1.0 else 0.0 end) > 0.40
