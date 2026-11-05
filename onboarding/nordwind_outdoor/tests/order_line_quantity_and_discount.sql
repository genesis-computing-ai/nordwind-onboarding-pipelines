-- Dictionary 3.8 and 3.10: QUANTITY >= 1, DISCOUNT_PCT between 0 and 100.
select *
from {{ ref('order_line') }}
where quantity < 1 or discount_pct < 0 or discount_pct > 100
