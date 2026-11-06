-- Value rules from the Partner Order Data Standard v1.2: QUANTITY >= 1, DISCOUNT_PCT 0..100, LINE_STATUS in its code set
select *
from {{ ref('order_line') }}
where quantity < 1
   or discount_pct < 0 or discount_pct > 100
   or line_status not in ('PLACED', 'SHIPPED', 'CANCELLED', 'RETURNED')
