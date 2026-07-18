with source as (
    select * from {{ source('raw', 'subskribe_subscriptions') }}
)

select
    subscription_id,
    account_id,
    upper(trim(subscription_state)) as subscription_state,
    cast(start_date as date) as subscription_start_date,
    cast(end_date as date) as subscription_end_date,
    cast(cancelled_date as date) as cancelled_date,
    nullif(trim(renewed_from_subscription_id), '') as renewed_from_subscription_id,
    cast(creation_time as timestamp) as created_at,
    cast(updated_at as timestamp) as updated_at
from source
