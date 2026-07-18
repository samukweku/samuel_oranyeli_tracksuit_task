with source as (
    select * from {{ source('raw', 'subskribe_accounts') }}
)

select
    account_id,
    trim(company_name) as account_company_name,
    nullif(trim(crmid), '') as crm_company_id,
    upper(trim(currency)) as account_currency,
    cast(created_at as date) as account_created_date
from source
