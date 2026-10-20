-- Grain: one row per Facebook ad (latest version by ad_updated_at).
with source as (

    select * from {{ source('facebook_ads', 'ads') }}

),

typed as (

    select
        cast(ad_id as string) as ad_id,
        cast(campaign_id as string) as campaign_id,
        cast(ad_group_id as string) as ad_group_id,
        cast(account_id as string) as account_id,
        ad_name,
        upper(trim(ad_status)) as ad_status,
        cast(ad_updated_at as timestamp) as updated_at
    from source

)

select * from typed
qualify row_number() over (partition by ad_id order by updated_at desc) = 1
