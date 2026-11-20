-- One row per order: fails on any ORDER_NO (per source) that appears twice.
select order_no, source_name, count(*) as n
from {{ ref('orders') }}
group by 1, 2
having count(*) > 1
