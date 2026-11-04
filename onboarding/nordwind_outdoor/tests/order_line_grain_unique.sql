-- One row per SOURCE_NAME + ORDER_ID + LINE_NUMBER (the standard's key).
select source_name, order_id, line_number, count(*) as n
from {{ ref('order_line') }}
group by 1, 2, 3
having count(*) > 1
