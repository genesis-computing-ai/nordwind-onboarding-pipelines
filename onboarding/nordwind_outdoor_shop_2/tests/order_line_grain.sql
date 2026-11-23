-- One row per (SOURCE_NAME, ORDER_ID, LINE_NUMBER), no key column empty.
select source_name, order_id, line_number, count(*) as n
from {{ ref('order_line') }}
group by source_name, order_id, line_number
having count(*) > 1 or source_name is null or order_id is null or line_number is null
