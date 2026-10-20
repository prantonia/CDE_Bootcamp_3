-- Grain: one row per platform x ad (ad_key).
-- Descriptive attributes of every ad that has reported performance, with its activity window.
-- Table: small, joined frequently, and cheaper to read than to re-aggregate on every query.
select
    ad_key,
    platform,
    source_ad_id,
    max(ad_name) as ad_name,
    max(ad_status) as ad_status,
    max(source_ad_group_id) as source_ad_group_id,
    max(ad_group_name) as ad_group_name,
    campaign_key,
    max(source_campaign_id) as source_campaign_id,
    max(campaign_name) as campaign_name,
    max(source_account_id) as source_account_id,
    max(account_name) as account_name,
    max(currency_code) as currency_code,
    min(report_date) as first_report_date,
    max(report_date) as last_report_date,
    count(distinct report_date) as reported_days
from {{ ref('int_marketing_ads') }}
group by ad_key, platform, source_ad_id, campaign_key
