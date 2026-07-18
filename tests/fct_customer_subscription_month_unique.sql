select
    subscription_month,
    subscription_id,
    count(*) as row_count
from {{ ref('fct_customer_subscription_month') }}
group by 1, 2
having count(*) > 1
