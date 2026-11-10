-- One row per SOURCE_NAME, ORDER_ID, LINE_NUMBER (dictionary section 2)
select SOURCE_NAME, ORDER_ID, LINE_NUMBER, count(*) as n
from {{ ref('order_line') }}
group by 1, 2, 3
having count(*) > 1
