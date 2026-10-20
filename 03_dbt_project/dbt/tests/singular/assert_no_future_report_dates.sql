-- A report date in the future means a bad extract (wrong date format, timezone shift, test data).
select
    platform,
    report_date,
    count(*) as bad_rows
from {{ ref('fct_marketing_ad_performance_daily') }}
where report_date > current_date
group by platform, report_date
