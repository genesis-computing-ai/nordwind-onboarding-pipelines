-- Dictionary section 2: every line belongs to an order in ORDERS, and every order has at least one line.
SELECT l.SOURCE_NAME, l.ORDER_ID, 'line without order' AS PROBLEM
FROM {{ ref('order_line') }} l
WHERE NOT EXISTS (SELECT 1 FROM {{ ref('orders') }} o
                  WHERE o.SOURCE_NAME = l.SOURCE_NAME AND o.ORDER_ID = l.ORDER_ID)
UNION ALL
SELECT o.SOURCE_NAME, o.ORDER_ID, 'order without line'
FROM {{ ref('orders') }} o
WHERE NOT EXISTS (SELECT 1 FROM {{ ref('order_line') }} l
                  WHERE l.SOURCE_NAME = o.SOURCE_NAME AND l.ORDER_ID = o.ORDER_ID)
