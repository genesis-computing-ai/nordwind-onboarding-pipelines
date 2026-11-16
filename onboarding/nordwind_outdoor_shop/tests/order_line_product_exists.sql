-- Dictionary section 2: every line's article is in PRODUCTS.
SELECT l.SOURCE_NAME, l.ORDER_ID, l.LINE_NUMBER, l.SKU
FROM {{ ref('order_line') }} l
WHERE NOT EXISTS (SELECT 1 FROM {{ ref('products') }} p
                  WHERE p.SOURCE_NAME = l.SOURCE_NAME AND p.SKU = l.SKU)
