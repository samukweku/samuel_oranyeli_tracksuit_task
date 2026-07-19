with companies as (
    select * from {{ ref('stg_hubspot__companies') }}
),

crm_customers as (
    select
        company_id as customer_id,
        company_id as crm_company_id,
        company_name as customer_name,
        customer_size_group,
        industry,
        country,
        created_date as crm_created_date,
        false as is_unmatched_crm_customer
    from companies
),

unmatched_billing_customers as (
    select
        customer_id,
        null as crm_company_id,
        account_company_name as customer_name,
        'Unknown' as customer_size_group,
        null as industry,
        null as country,
        null as crm_created_date,
        is_unmatched_crm_customer
    from {{ ref('int_billing_account_customer') }}
    where is_unmatched_crm_customer
)

select * from crm_customers
union all
select * from unmatched_billing_customers
