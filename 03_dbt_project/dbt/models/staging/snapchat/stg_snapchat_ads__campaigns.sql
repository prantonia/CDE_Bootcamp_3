-- Grain: one row per Snapchat campaign.
with source as (

    select * from {{ source('snapchat_ads', 'campaigns') }}

)

select
    cast(campaign_id as string) as campaign_id,
    cast(account_id as string) as account_id,
    campaign_name
from source
