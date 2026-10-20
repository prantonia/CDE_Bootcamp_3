-- Grain: one row per Snapchat ad (latest version by ad_detail_updated_at).
-- Snapchat does not expose an ad status, so none is selected here.
with source as (

    select * from {{ source('snapchat_ads', 'ads') }}

),

typed as (

    select
        cast(ad_id as string) as ad_id,
        cast(ad_group_id as string) as ad_group_id,
        ad_name,
        cast(ad_detail_updated_at as timestamp) as updated_at
    from source

)

select * from typed
qualify row_number() over (partition by ad_id order by updated_at desc) = 1
