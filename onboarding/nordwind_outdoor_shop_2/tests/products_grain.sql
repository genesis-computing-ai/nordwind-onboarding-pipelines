-- One row per (SOURCE_NAME, SKU), no key column empty.
select source_name, sku, count(*) as n
from {{ ref('products') }}
group by source_name, sku
having count(*) > 1 or source_name is null or sku is null
