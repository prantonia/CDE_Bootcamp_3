-- Grain: one row per Snapchat ad group (latest version by ad_group_updated_at).
-- The source holds several versions for some ad groups. Joining ads to it without this
-- reduction would duplicate fact rows (63 ads -> 88 rows in the sample data).
with source as (

    select * from {{ source('snapchat_ads', 'ad_groups') }}

),

typed as (

    select
        cast(ad_group_id as string) as ad_group_id,
        cast(campaign_id as string) as campaign_id,
        ad_group_name,
        cast(ad_group_updated_at as timestamp) as updated_at
    from source

)

select * from typed
qualify row_number() over (partition by ad_group_id order by updated_at desc) = 1
