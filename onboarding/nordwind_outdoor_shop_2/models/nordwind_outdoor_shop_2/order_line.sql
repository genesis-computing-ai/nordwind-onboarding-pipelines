-- depends_on: {{ ref('customers') }}
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'order_id', 'line_number'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    full_refresh=(false if target.name == 'prod' else none),
    on_schema_change='fail'
) }}

-- Mapping: mapping_ORDER_LINE.sql as the owner approved it (mission repo, commit f1a0aab), orders_raw bound to bronze.
WITH orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'orders_raw') }}
),
latest AS (
    -- [High] one row per order line; the newest file by the date in its name wins (dictionary section 1, Keys)
    -- [Medium] ASSUMPTION A2: ties on the file date are broken by load time, then file name
    SELECT *
    FROM orders_raw
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(ORDER_NO)), TRY_TO_NUMBER(TRIM(POS))
        ORDER BY TRY_TO_DATE(REGEXP_SUBSTR(_SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}')) DESC NULLS LAST,
                 _LOADED_AT::TIMESTAMP_TZ DESC,
                 _SOURCE_FILE DESC
    ) = 1
),
typed AS (
    SELECT
        latest.*,
        CAST(TRY_TO_NUMBER(REPLACE(REPLACE(TRIM(PRICE), '.', ''), ',', '.'), 18, 2) AS NUMBER(18,2)) AS unit_price_n,
        CAST(COALESCE(TRY_TO_NUMBER(REPLACE(REPLACE(REPLACE(TRIM(DISCOUNT), '%', ''), ' ', ''), ',', '.'), 5, 2), 0) AS NUMBER(5,2)) AS discount_pct_n,
        CAST(TRY_TO_NUMBER(TRIM(QTY)) AS NUMBER(9,0)) AS quantity_n
    FROM latest
)
SELECT
    CAST('{{ var("source_name") }}' AS VARCHAR(64)) AS SOURCE_NAME,            -- [High] kickoff source_name
    CAST(UPPER(TRIM(ORDER_NO)) AS VARCHAR(64)) AS ORDER_ID,                   -- [High] refers to ORDERS, stored by its key rule
    CAST(TRY_TO_NUMBER(TRIM(POS)) AS NUMBER(9,0)) AS LINE_NUMBER,             -- [High] section 6: position within the order
    CAST(UPPER(TRIM(ARTICLE)) AS VARCHAR(64)) AS SKU,                         -- [High] refers to PRODUCTS, stored by its key rule
    quantity_n AS QUANTITY,                                                    -- [High] section 6: units ordered
    unit_price_n AS UNIT_PRICE,                                                -- [High] section 1 Amounts: 1.249,50 reads 1249.50
    discount_pct_n AS DISCOUNT_PCT,                                            -- [High] section 6: 10, 10% and 10 % mean 10; 0 when none
    CAST(ROUND(quantity_n * unit_price_n * (1 - discount_pct_n / 100), 2) AS NUMBER(18,2)) AS NET_AMOUNT, -- [High] section 6 formula, half up
    CAST(CASE
        WHEN LOWER(TRIM(STATUS)) IN ('placed', 'new', 'open', 'ordered') THEN 'PLACED'
        WHEN LOWER(TRIM(STATUS)) IN ('shipped', 'sent', 'dispatched') THEN 'SHIPPED'
        WHEN LOWER(TRIM(STATUS)) IN ('cancelled', 'canceled', 'void') THEN 'CANCELLED'
        WHEN LOWER(TRIM(STATUS)) IN ('returned', 'refunded') THEN 'RETURNED'
    END AS VARCHAR(16)) AS LINE_STATUS,                                        -- [High] section 7 LINE_STATUS; A1: an unknown spelling stays NULL and fails the not-null check
    CAST(REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$') AS VARCHAR(255)) AS SOURCE_FILE, -- [High] file name without its folder
    CONVERT_TIMEZONE('UTC', _LOADED_AT::TIMESTAMP_TZ)::TIMESTAMP_NTZ AS LOADED_AT_UTC -- [High] load time, UTC
FROM typed
