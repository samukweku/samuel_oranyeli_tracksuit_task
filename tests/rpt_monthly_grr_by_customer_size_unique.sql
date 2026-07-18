select
    report_month,
    customer_size_group,
    count(*) as row_count
from {{ ref('rpt_monthly_grr_by_customer_size') }}
group by 1, 2
having count(*) > 1
