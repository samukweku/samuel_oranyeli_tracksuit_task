with current_company_ids as (
    select company_id as source_company_id, company_id as resolved_company_id
    from {{ ref('stg_hubspot__companies') }}
),

merged_company_ids as (
    select trim(merged_company_id) as source_company_id, company_id as resolved_company_id
    from {{ ref('stg_hubspot__companies') }},
    unnest(string_split(merged_object_ids, ';')) as merged_ids(merged_company_id)
    where merged_object_ids is not null
)

select * from current_company_ids
union all
select * from merged_company_ids
