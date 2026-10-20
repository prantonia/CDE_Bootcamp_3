-- Grain: one row per Facebook ad per day (ad_id, report_date).
with source as (

    select * from {{ source('facebook_ads', 'ad_stats') }}

),

typed as (

    select
        cast(ad_id as string) as ad_id,
        cast(account_id as string) as account_id,
        cast(ad_date as date) as report_date,
        cast(ad_spend as decimal(18, 6)) as spend,
        -- The extract encodes "not reported" as the text 'null'. Keep it NULL: unknown is not zero.
        -- try_cast (not cast) so an unexpected string becomes NULL instead of failing the run under
        -- ANSI mode; the missing-metrics warning test would flag it if that ever became common.
        try_cast(nullif(lower(trim(ad_impressions)), 'null') as bigint) as impressions,
        try_cast(nullif(lower(trim(ad_clicks)), 'null') as bigint) as clicks
    from source

)

select * from typed
