{{ config(materialized='table') }}

with account_customers as (
    select
        accounts.account_id,
        coalesce(id_map.resolved_company_id, 'unmatched:' || accounts.account_id) as customer_id
    from {{ ref('stg_subskribe__accounts') }} as accounts
    left join {{ ref('int_customer_id_map') }} as id_map
        on accounts.crm_company_id = id_map.source_company_id
)

select
    subscriptions.subscription_id,
    subscriptions.account_id,
    account_customers.customer_id,
    subscriptions.subscription_state,
    subscriptions.subscription_start_date,
    subscriptions.subscription_end_date,
    subscriptions.cancelled_date,
    subscriptions.renewed_from_subscription_id,
    subscriptions.created_at,
    subscriptions.updated_at
from {{ ref('stg_subskribe__subscriptions') }} as subscriptions
inner join account_customers
    on subscriptions.account_id = account_customers.account_id
