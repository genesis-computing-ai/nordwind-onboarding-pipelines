-- Dictionary section 2: every non-guest order names a customer in CUSTOMERS, and every order has at least one line,
-- within the same partner.
select o.source_name, o.order_id
from {{ ref('orders') }} o
left join {{ ref('customers') }} c on c.source_name = o.source_name and c.customer_id = o.customer_id
where (o.customer_id is not null and c.customer_id is null)
   or not exists (
       select 1 from {{ ref('order_line') }} l
       where l.source_name = o.source_name and l.order_id = o.order_id
   )
