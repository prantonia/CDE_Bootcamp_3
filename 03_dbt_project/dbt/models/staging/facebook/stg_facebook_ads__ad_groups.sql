-- Grain: one row per Facebook ad group (latest version by ad_group_updated_at).
with source as (

    select * from {{ source('facebook_ads', 'ad_groups') }}

),

typed as (

    select
        cast(ad_group_id as string) as ad_group_id,
        ad_group_name,
        cast(ad_group_updated_at as timestamp) as updated_at
    from source

)

select * from typed
qualify row_number() over (partition by ad_group_id order by updated_at desc) = 1
