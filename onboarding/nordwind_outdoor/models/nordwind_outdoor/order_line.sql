{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'order_id', 'line_number'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none),
    pre_hook=[
        "{{ nordwind_bronze_create_schema() }}",
        "{{ nordwind_bronze_create_table() }}",
        "{{ nordwind_bronze_copy_into() }}",
    ],
) }}

-- The committed mapping SQL (mapping_ORDER_LINE.sql, approved by the owner at commit 8b50ec1)
-- with the nordwind_orders_raw CTE bound to bronze. The owner's time zone and the source name
-- are read from the project variables source_time_zone and source_name.
WITH nordwind_orders_raw AS (
  SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, _SOURCE_FILE, _LOADED_AT
  FROM {{ source('bronze', 'nordwind_orders_raw') }}
),
cleaned AS (
  SELECT r.*,
    SPLIT_PART(_SOURCE_FILE, '/', -1) AS src_file_name,
    TRY_TO_DATE(REGEXP_SUBSTR(SPLIT_PART(_SOURCE_FILE, '/', -1), '[0-9]{4}-[0-9]{2}-[0-9]{2}')) AS src_file_date,
    TO_TIMESTAMP_NTZ(TRIM(CREATED), 'YYYY-MM-DD HH24:MI:SS') AS created_local,
    -- [Medium] ASSUMPTION A3: a price with a comma is decimal-comma (dots are thousands); one without a comma is read as written
    TO_NUMBER(IFF(CONTAINS(TRIM(PRICE), ','), REPLACE(REPLACE(TRIM(PRICE), '.', ''), ',', '.'), TRIM(PRICE)), 18, 2) AS unit_price,
    TO_NUMBER(COALESCE(NULLIF(REPLACE(REPLACE(REPLACE(TRIM(DISCOUNT), '%', ''), ' ', ''), ',', '.'), ''), '0'), 5, 2) AS discount_pct,
    TO_NUMBER(TRIM(QTY), 9, 0) AS quantity,
    _LOADED_AT::TIMESTAMP_TZ AS loaded_tz
  FROM nordwind_orders_raw r
)
SELECT
  CAST('{{ var("source_name") }}' AS VARCHAR(64)) AS SOURCE_NAME,
  CAST(UPPER(TRIM(ORDER_NO)) AS VARCHAR(64)) AS ORDER_ID,
  CAST(TO_NUMBER(TRIM(POS), 9, 0) AS NUMBER(9,0)) AS LINE_NUMBER,
  CAST(CONVERT_TIMEZONE('{{ var("source_time_zone") }}', 'UTC', created_local) AS TIMESTAMP_NTZ) AS ORDERED_AT_UTC,
  CAST(created_local AS DATE) AS ORDER_DATE,
  -- [Medium] ASSUMPTION A2: an empty CUSTOMER is a guest checkout -> NULL; otherwise trimmed
  CAST(NULLIF(TRIM(CUSTOMER), '') AS VARCHAR(64)) AS CUSTOMER_REF,
  CAST(UPPER(TRIM(ARTICLE)) AS VARCHAR(64)) AS SKU,
  CAST(quantity AS NUMBER(9,0)) AS QUANTITY,
  CAST(unit_price AS NUMBER(18,2)) AS UNIT_PRICE,
  CAST(discount_pct AS NUMBER(5,2)) AS DISCOUNT_PCT,
  CAST(ROUND(quantity * unit_price * (1 - discount_pct / 100), 2) AS NUMBER(18,2)) AS NET_AMOUNT,
  CAST(UPPER(TRIM(CUR)) AS VARCHAR(3)) AS CURRENCY_CODE,
  CAST(CASE
    WHEN LOWER(TRIM(STATUS)) IN ('placed','new','open','ordered') THEN 'PLACED'
    WHEN LOWER(TRIM(STATUS)) IN ('shipped','sent','dispatched') THEN 'SHIPPED'
    WHEN LOWER(TRIM(STATUS)) IN ('cancelled','canceled','void') THEN 'CANCELLED'
    WHEN LOWER(TRIM(STATUS)) IN ('returned','refunded') THEN 'RETURNED'
  END AS VARCHAR(16)) AS LINE_STATUS,
  -- [Medium] ASSUMPTION A4: any other two-letter value is taken as its ISO code
  CAST(CASE
    WHEN NULLIF(TRIM(SHIP_TO), '') IS NULL THEN NULL
    WHEN UPPER(TRIM(SHIP_TO)) IN ('DE','GERMANY','DEUTSCHLAND') THEN 'DE'
    WHEN UPPER(TRIM(SHIP_TO)) IN ('AT','AUSTRIA','ÖSTERREICH','OESTERREICH') THEN 'AT'
    WHEN UPPER(TRIM(SHIP_TO)) IN ('CH','SWITZERLAND','SCHWEIZ') THEN 'CH'
    WHEN REGEXP_LIKE(UPPER(TRIM(SHIP_TO)), '[A-Z]{2}') THEN UPPER(TRIM(SHIP_TO))
  END AS VARCHAR(2)) AS SHIP_COUNTRY,
  CAST(src_file_name AS VARCHAR(255)) AS SOURCE_FILE,
  CAST(CONVERT_TIMEZONE('UTC', loaded_tz) AS TIMESTAMP_NTZ) AS LOADED_AT_UTC
FROM cleaned
-- [Medium] ASSUMPTION A1: latest state per key = the row from the newest file by the date in its name, then the latest load
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY UPPER(TRIM(ORDER_NO)), TO_NUMBER(TRIM(POS), 9, 0)
  ORDER BY src_file_date DESC NULLS LAST, loaded_tz DESC, src_file_name DESC) = 1
