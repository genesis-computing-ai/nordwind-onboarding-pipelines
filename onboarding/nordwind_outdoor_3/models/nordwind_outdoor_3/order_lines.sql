-- depends_on: {{ ref('orders') }}
-- ORDERS loads the bronze table in its pre_hooks; this model runs after it and reads the same bronze table.
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['order_no', 'line_no', 'source_name'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none),
) }}

-- Mapping: Nordwind order feed -> NORDWIND_OUTDOOR_3.ORDER_LINES
-- The approved mapping_ORDER_LINES.sql (mission commit f3e7f95e), with nordwind_orders_raw reading bronze.
WITH nordwind_orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'nordwind_orders_raw') }}
),
latest AS (
    SELECT *, REGEXP_SUBSTR(_SOURCE_FILE, '\\d{4}-\\d{2}-\\d{2}') AS file_date
    FROM nordwind_orders_raw
)
SELECT
    -- [High] order number, trimmed; joins ORDERS.ORDER_NO
    TRIM(ORDER_NO)::VARCHAR(20) AS ORDER_NO,
    -- [High] position within the order, 1-5
    TO_NUMBER(TRIM(POS))::NUMBER(5,0) AS LINE_NO,
    -- [High] article code, trimmed and upper-cased (67 spellings -> 40 articles)
    UPPER(TRIM(ARTICLE))::VARCHAR(40) AS ARTICLE_CODE,
    -- [High] integer quantity, 1-4
    TO_NUMBER(TRIM(QTY))::NUMBER(9,0) AS QUANTITY,
    -- [High] decimal comma with thousands dot (1.049,00 -> 1049.00); 412/412 parse and round-trip
    TO_DECIMAL(REPLACE(REPLACE(TRIM(PRICE), '.', ''), ',', '.'), 12, 2) AS UNIT_PRICE,
    -- [Medium] ASSUMPTION A2: blank discount means no discount (0); '5', '5%', '5 %' all mean 5 percent
    COALESCE(TO_DECIMAL(NULLIF(REPLACE(REPLACE(DISCOUNT, '%', ''), ' ', ''), ''), 5, 2), 0)::NUMBER(5,2) AS DISCOUNT_PCT,
    -- [High] status, trimmed and lower-cased, 'canceled' -> 'cancelled': placed, shipped, cancelled, returned
    (CASE LOWER(TRIM(STATUS)) WHEN 'canceled' THEN 'cancelled' ELSE LOWER(TRIM(STATUS)) END)::VARCHAR(20) AS LINE_STATUS,
    -- [High] kickoff source_name
    'nordwind_outdoor_3'::VARCHAR(50) AS SOURCE_NAME,
    -- [High] file name only: text after the last /
    REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$')::VARCHAR(200) AS SOURCE_FILE,
    -- [High] load time; one cast reads the snapshot's ISO text and bronze's timestamp
    _LOADED_AT::TIMESTAMP_TZ AS LOADED_AT
FROM latest
-- [Medium] ASSUMPTION A4: a line resent in a later file takes the newest file's version (by the date in the file name)
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(ORDER_NO), TO_NUMBER(TRIM(POS)) ORDER BY file_date DESC, _LOADED_AT::TIMESTAMP_TZ DESC) = 1
