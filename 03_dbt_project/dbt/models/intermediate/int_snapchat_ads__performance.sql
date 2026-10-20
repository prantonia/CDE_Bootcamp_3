-- Grain: one row per Snapchat ad per day per country (same as stg_snapchat_ads__ad_stats).
-- Ephemeral: only int_marketing_ads reads it, so it is inlined as a CTE instead of stored.
{{ config(materialized='ephemeral') }}

with stats as (

    select * from {{ ref('stg_snapchat_ads__ad_stats') }}

),

ads as (

    select * from {{ ref('stg_snapchat_ads__ads') }}

),

ad_groups as (

    select * from {{ ref('stg_snapchat_ads__ad_groups') }}

),

campaigns as (

    select * from {{ ref('stg_snapchat_ads__campaigns') }}

)

select
    'snapchat' as platform,
    stats.ad_id as source_ad_id,
    stats.report_date,
    stats.country_code,
    campaigns.account_id as source_account_id,
    -- Snapchat extracts carry no account table: no account name, currency comes from the stats row.
    cast(null as string) as account_name,
    stats.currency_code,
    ad_groups.campaign_id as source_campaign_id,
    campaigns.campaign_name,
    ads.ad_group_id as source_ad_group_id,
    ad_groups.ad_group_name,
    ads.ad_name,
    -- Snapchat exposes no ad status.
    cast(null as string) as ad_status,
    stats.spend,
    stats.impressions,
    stats.clicks
from stats
left join ads on stats.ad_id = ads.ad_id
left join ad_groups on ads.ad_group_id = ad_groups.ad_group_id
left join campaigns on ad_groups.campaign_id = campaigns.campaign_id
