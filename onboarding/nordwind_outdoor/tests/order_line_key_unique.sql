-- The table's key (dictionary section 2): one row per SOURCE_NAME, ORDER_ID, LINE_NUMBER.
select source_name, order_id, line_number, count(*) as n
from {{ ref('order_line') }}
group by 1, 2, 3
having count(*) > 1
