-- Grain: one row per SOURCE_NAME, ORDER_ID, LINE_NUMBER (Partner Order Data Standard v1.2, s.2)
select source_name, order_id, line_number, count(*) as n
from {{ ref('order_line') }}
group by 1, 2, 3
having count(*) > 1
