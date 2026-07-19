select
    accounts.account_id,
    accounts.account_company_name,
    accounts.crm_company_id,
    accounts.account_currency,
    accounts.account_created_date,
    coalesce(id_map.resolved_company_id, 'unmatched:' || accounts.account_id) as customer_id,
    id_map.resolved_company_id is null as is_unmatched_crm_customer
from {{ ref('stg_subskribe__accounts') }} as accounts
left join {{ ref('int_customer_id_map') }} as id_map
    on accounts.crm_company_id = id_map.source_company_id
