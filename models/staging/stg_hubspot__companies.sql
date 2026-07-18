with source as (
    select * from {{ source('raw', 'hubspot_companies') }}
)

select
    company_id,
    trim(company_name) as company_name,
    nullif(trim(size_grouped), '') as customer_size_group,
    nullif(trim(industry), '') as industry,
    nullif(trim(country), '') as country,
    nullif(trim(merged_object_ids), '') as merged_object_ids,
    cast(created_at as date) as created_date
from source
