-- The dictionary's rules a NOT NULL cannot express: QUANTITY >= 1, DISCOUNT_PCT 0..100, the status code set.
select *
from {{ ref('order_line') }}
where quantity < 1
   or discount_pct not between 0 and 100
   or line_status not in ('PLACED', 'SHIPPED', 'CANCELLED', 'RETURNED')
