{{ config(materialized='table') }}

with account_customers as (
    select
        accounts.account_id,
        coalesce(id_map.resolved_company_id, 'unmatched:' || accounts.account_id) as customer_id
    from {{ ref('stg_subskribe__accounts') }} as accounts
    left join {{ ref('int_customer_id_map') }} as id_map
        on accounts.crm_company_id = id_map.source_company_id
),

subscription_months as (
    select
        subscriptions.subscription_id,
        subscriptions.account_id,
        account_customers.customer_id,
        subscriptions.subscription_state,
        subscriptions.subscription_start_date,
        subscriptions.subscription_end_date,
        subscriptions.cancelled_date,
        subscriptions.renewed_from_subscription_id,
        cast(months.subscription_month as date) as subscription_month
    from {{ ref('stg_subskribe__subscriptions') }} as subscriptions
    inner join account_customers on subscriptions.account_id = account_customers.account_id,
    unnest(generate_series(
        date_trunc('month', subscriptions.subscription_start_date),
        date_trunc('month', subscriptions.subscription_end_date),
        interval 1 month
    )) as months(subscription_month)
),

monthly_subscription_revenue as (
    select
        subscription_id,
        invoice_month,
        count(*) as recognised_invoice_count,
        sum(invoice_total_nzd) as recognised_revenue_nzd
    from {{ ref('stg_subskribe__invoices') }}
    where is_recognised_revenue
    group by 1, 2
)

select
    subscription_months.subscription_month,
    subscription_months.subscription_id,
    subscription_months.account_id,
    subscription_months.customer_id,
    customers.customer_name,
    customers.customer_size_group,
    customers.industry,
    customers.country,
    customers.is_unmatched_crm_customer,
    subscription_months.subscription_state,
    subscription_months.subscription_start_date,
    subscription_months.subscription_end_date,
    subscription_months.cancelled_date,
    subscription_months.renewed_from_subscription_id,
    true as is_subscription_active_in_month,
    coalesce(revenue.recognised_invoice_count, 0) as recognised_invoice_count,
    coalesce(revenue.recognised_revenue_nzd, 0) as recognised_revenue_nzd,
    coalesce(revenue.recognised_revenue_nzd, 0) > 0 as has_recognised_revenue
from subscription_months
inner join {{ ref('dim_customer') }} as customers
    on subscription_months.customer_id = customers.customer_id
left join monthly_subscription_revenue as revenue
    on subscription_months.subscription_id = revenue.subscription_id
    and subscription_months.subscription_month = revenue.invoice_month
