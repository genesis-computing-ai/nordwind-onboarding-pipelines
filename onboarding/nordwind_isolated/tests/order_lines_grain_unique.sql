-- One row per order line: fails on any (ORDER_NO, LINE_NO) (per source) that appears twice.
select order_no, line_no, source_name, count(*) as n
from {{ ref('order_lines') }}
group by 1, 2, 3
having count(*) > 1
