{{ config(materialized='table') }}

with bounds as (
    select
        least(
            (select min(subscription_start_date) from {{ ref('stg_subskribe__subscriptions') }}),
            (select min(invoice_date) from {{ ref('stg_subskribe__invoices') }})
        ) as start_date,
        greatest(
            (select max(subscription_end_date) from {{ ref('stg_subskribe__subscriptions') }}),
            (select max(invoice_date) from {{ ref('stg_subskribe__invoices') }})
        ) as end_date
),

dates as (
    select cast(calendar_date as date) as date_day
    from bounds,
    unnest(generate_series(start_date, end_date, interval 1 day)) as days(calendar_date)
)

select
    date_day,
    cast(date_trunc('month', date_day) as date) as month_start_date,
    cast(date_trunc('quarter', date_day) as date) as quarter_start_date,
    extract(year from date_day) as calendar_year,
    extract(quarter from date_day) as calendar_quarter,
    extract(month from date_day) as calendar_month,
    extract(day from date_day) as day_of_month,
    dayname(date_day) as day_name,
    dayofweek(date_day) between 1 and 5 as is_weekday
from dates
