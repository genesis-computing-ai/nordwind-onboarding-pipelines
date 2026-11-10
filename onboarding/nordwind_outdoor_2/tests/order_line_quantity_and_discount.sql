-- QUANTITY >= 1 and DISCOUNT_PCT between 0 and 100 (dictionary section 3)
select *
from {{ ref('order_line') }}
where QUANTITY < 1 or DISCOUNT_PCT < 0 or DISCOUNT_PCT > 100
