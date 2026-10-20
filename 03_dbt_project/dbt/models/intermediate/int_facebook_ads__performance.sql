-- Grain: one row per Facebook ad per day (same as stg_facebook_ads__ad_stats).
-- Ephemeral: only int_marketing_ads reads it, so it is inlined as a CTE instead of stored.
{{ config(materialized='ephemeral') }}

with stats as (

    select * from {{ ref('stg_facebook_ads__ad_stats') }}

),

ads as (

    select * from {{ ref('stg_facebook_ads__ads') }}

),

ad_groups as (

    select * from {{ ref('stg_facebook_ads__ad_groups') }}

),

campaigns as (

    select * from {{ ref('stg_facebook_ads__campaigns') }}

),

accounts as (

    select * from {{ ref('stg_facebook_ads__accounts') }}

)

select
    'facebook' as platform,
    stats.ad_id as source_ad_id,
    stats.report_date,
    -- Facebook stats are not broken down by country.
    cast(null as string) as country_code,
    stats.account_id as source_account_id,
    accounts.account_name,
    accounts.currency_code,
    ads.campaign_id as source_campaign_id,
    campaigns.campaign_name,
    ads.ad_group_id as source_ad_group_id,
    ad_groups.ad_group_name,
    ads.ad_name,
    ads.ad_status,
    stats.spend,
    stats.impressions,
    stats.clicks
from stats
left join ads on stats.ad_id = ads.ad_id
left join ad_groups on ads.ad_group_id = ad_groups.ad_group_id
left join campaigns on ads.campaign_id = campaigns.campaign_id
left join accounts on stats.account_id = accounts.account_id
