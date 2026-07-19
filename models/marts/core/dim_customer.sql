with companies as (
    select * from {{ ref('stg_hubspot__companies') }}
),

account_mappings as (
    select accounts.account_id, accounts.account_company_name, id_map.resolved_company_id
    from {{ ref('stg_subskribe__accounts') }} as accounts
    left join {{ ref('int_customer_id_map') }} as id_map
        on accounts.crm_company_id = id_map.source_company_id
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
        'unmatched:' || account_id as customer_id,
        null as crm_company_id,
        account_company_name as customer_name,
        'Unknown' as customer_size_group,
        null as industry,
        null as country,
        null as crm_created_date,
        true as is_unmatched_crm_customer
    from account_mappings
    where resolved_company_id is null
)

select * from crm_customers
union all
select * from unmatched_billing_customers
