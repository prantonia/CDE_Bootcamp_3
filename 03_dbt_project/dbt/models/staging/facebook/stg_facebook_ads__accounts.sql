-- Grain: one row per Facebook ad account (latest version by account_updated_at).
with source as (

    select * from {{ source('facebook_ads', 'accounts') }}

),

typed as (

    select
        cast(account_id as string) as account_id,
        account_name,
        upper(trim(ad_currency_code)) as currency_code,
        cast(account_created_at as timestamp) as created_at,
        cast(account_updated_at as timestamp) as updated_at
    from source

)

select * from typed
qualify row_number() over (partition by account_id order by updated_at desc) = 1
