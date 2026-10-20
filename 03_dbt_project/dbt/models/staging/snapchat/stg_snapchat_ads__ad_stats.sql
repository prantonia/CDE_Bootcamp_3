-- Grain: one row per Snapchat ad per day per country (ad_id, report_date, country_code).
with source as (

    select * from {{ source('snapchat_ads', 'ad_stats') }}

),

typed as (

    select
        -- Snapchat calls the ad id `ad_detail_id`; renamed so both platforms expose `ad_id`.
        cast(ad_detail_id as string) as ad_id,
        cast(ad_date as date) as report_date,
        upper(trim(ad_country)) as country_code,
        upper(trim(ad_currency_code)) as currency_code,
        cast(ad_spend as decimal(18, 6)) as spend,
        try_cast(nullif(lower(trim(ad_impressions)), 'null') as bigint) as impressions,
        try_cast(nullif(lower(trim(ad_clicks)), 'null') as bigint) as clicks
    from source

)

select * from typed
