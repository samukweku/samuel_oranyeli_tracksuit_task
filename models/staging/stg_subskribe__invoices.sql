with source as (
    select * from {{ source('raw', 'subskribe_invoices') }}
)

select
    invoice_id,
    account_id,
    subscription_id,
    cast(invoice_date as date) as invoice_date,
    cast(date_trunc('month', cast(invoice_date as date)) as date) as invoice_month,
    cast(total as decimal(18, 2)) as invoice_total,
    cast(total_nzd as decimal(18, 2)) as invoice_total_nzd,
    upper(trim(currency)) as invoice_currency,
    upper(trim(status)) as invoice_status,
    upper(trim(status)) in ('PAID', 'POSTED') as is_recognised_revenue
from source
