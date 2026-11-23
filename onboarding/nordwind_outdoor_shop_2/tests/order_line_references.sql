-- Dictionary section 2: every line belongs to an order in ORDERS and its article is in PRODUCTS,
-- within the same partner.
select l.source_name, l.order_id, l.line_number, l.sku
from {{ ref('order_line') }} l
left join {{ ref('orders') }} o on o.source_name = l.source_name and o.order_id = l.order_id
left join {{ ref('products') }} p on p.source_name = l.source_name and p.sku = l.sku
where o.order_id is null or p.sku is null
