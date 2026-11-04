-- QUANTITY is at least 1 (standard comment).
select * from {{ ref('order_line') }} where quantity < 1
