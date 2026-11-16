-- Dictionary section 2: every order placed by a customer account names a customer in CUSTOMERS.
SELECT o.SOURCE_NAME, o.ORDER_ID, o.CUSTOMER_ID
FROM {{ ref('orders') }} o
WHERE o.CUSTOMER_ID IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM {{ ref('customers') }} c
                  WHERE c.SOURCE_NAME = o.SOURCE_NAME AND c.CUSTOMER_ID = o.CUSTOMER_ID)
