-- Grain: one row per Facebook campaign (latest version by campaign_updated_at).
with source as (

    select * from {{ source('facebook_ads', 'campaigns') }}

),

typed as (

    select
        cast(campaign_id as string) as campaign_id,
        campaign_name,
        cast(campaign_updated_at as timestamp) as updated_at
    from source

)

select * from typed
qualify row_number() over (partition by campaign_id order by updated_at desc) = 1
