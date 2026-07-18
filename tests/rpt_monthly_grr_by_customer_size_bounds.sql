select *
from {{ ref('rpt_monthly_grr_by_customer_size') }}
where gross_revenue_retention_pct < 0
   or gross_revenue_retention_pct > 100
