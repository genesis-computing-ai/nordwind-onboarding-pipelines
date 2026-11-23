-- One row per (SOURCE_NAME, CUSTOMER_ID), no key column empty.
select source_name, customer_id, count(*) as n
from {{ ref('customers') }}
group by source_name, customer_id
having count(*) > 1 or source_name is null or customer_id is null
