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
inner join {{ ref('int_billing_account_customer') }} as account_customers
    on subscriptions.account_id = account_customers.account_id
