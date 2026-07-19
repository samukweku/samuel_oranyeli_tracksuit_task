-- Anchor to available data, rather than the machine date, for reproducible extracts.
with customer_monthly_revenue as (
    select
        invoices.invoice_month,
        invoices.customer_id,
        customers.customer_size_group,
        sum(invoices.invoice_total_nzd) as revenue_nzd
    from {{ ref('fct_subscription_invoice') }} as invoices
    inner join {{ ref('dim_customer') }} as customers
        on invoices.customer_id = customers.customer_id
    where invoices.is_recognised_revenue
    group by 1, 2, 3
),

latest_available_month as (
    select max(invoice_month) as month_start
    from customer_monthly_revenue
    where revenue_nzd > 0
),

reporting_months as (
    select distinct month_start_date as report_month
    from {{ ref('dim_date') }}
    cross join latest_available_month
    where month_start_date between month_start - interval 11 month and month_start
),

cohort_revenue as (
    select
        reporting_months.report_month,
        baseline.customer_size_group,
        baseline.customer_id,
        baseline.revenue_nzd as cohort_revenue_nzd,
        coalesce(current_month.revenue_nzd, 0) as current_revenue_nzd
    from reporting_months
    inner join customer_monthly_revenue as baseline
        on baseline.invoice_month = reporting_months.report_month - interval 12 month
        and baseline.revenue_nzd > 0
    left join customer_monthly_revenue as current_month
        on current_month.invoice_month = reporting_months.report_month
        and current_month.customer_id = baseline.customer_id
)

select
    report_month,
    customer_size_group,
    count(*) as cohort_customer_count,
    sum(cohort_revenue_nzd) as cohort_revenue_nzd,
    sum(current_revenue_nzd) as current_cohort_revenue_nzd,
    sum(least(current_revenue_nzd, cohort_revenue_nzd)) as retained_revenue_nzd,
    round(
        100.0 * sum(least(current_revenue_nzd, cohort_revenue_nzd))
        / nullif(sum(cohort_revenue_nzd), 0),
        2
    ) as gross_revenue_retention_pct
from cohort_revenue
group by 1, 2
order by 1, 2
