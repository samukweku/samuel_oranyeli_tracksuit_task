select
    invoices.invoice_id,
    invoices.invoice_date,
    dates.month_start_date as invoice_month,
    invoices.subscription_id,
    subscriptions.account_id,
    subscriptions.customer_id,
    invoices.invoice_total,
    invoices.invoice_total_nzd,
    invoices.invoice_currency,
    invoices.invoice_status,
    invoices.is_recognised_revenue
from {{ ref('stg_subskribe__invoices') }} as invoices
inner join {{ ref('dim_subscription') }} as subscriptions
    on invoices.subscription_id = subscriptions.subscription_id
inner join {{ ref('dim_date') }} as dates
    on invoices.invoice_date = dates.date_day
