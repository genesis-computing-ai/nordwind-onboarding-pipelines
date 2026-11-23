-- One row per (SOURCE_NAME, ORDER_ID), no key column empty.
select source_name, order_id, count(*) as n
from {{ ref('orders') }}
group by source_name, order_id
having count(*) > 1 or source_name is null or order_id is null
