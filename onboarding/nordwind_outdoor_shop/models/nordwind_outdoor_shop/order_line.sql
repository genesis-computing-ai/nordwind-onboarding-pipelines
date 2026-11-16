-- depends_on: {{ ref('customers') }}
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'order_id', 'line_number'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none)
) }}
-- Approved mapping: mapping_ORDER_LINE.sql (mission repo, commit 01bcefd), orders_raw bound to bronze.
WITH orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'orders_raw') }}
),
ranked AS (
    SELECT r.*,
           REGEXP_SUBSTR(r._SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}') AS FILE_DATE,
           r._LOADED_AT::timestamp_tz AS LOADED_TZ,
           TO_NUMBER(TRIM(r.QTY)) AS QTY_N,
           CAST(REPLACE(REPLACE(TRIM(r.PRICE), '.', ''), ',', '.') AS NUMBER(18, 2)) AS PRICE_N,
           CAST(COALESCE(NULLIF(TRIM(REPLACE(REPLACE(r.DISCOUNT, '%', ''), ',', '.')), ''), '0') AS NUMBER(5, 2)) AS DISC_N
    FROM orders_raw r
),
latest AS (
    SELECT * FROM ranked
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(ORDER_NO)), TO_NUMBER(TRIM(POS))
                               ORDER BY FILE_DATE DESC, LOADED_TZ DESC, _SOURCE_FILE DESC) = 1
)
SELECT
    CAST('nordwind_outdoor_shop' AS VARCHAR(64))                       AS SOURCE_NAME,
    CAST(UPPER(TRIM(ORDER_NO)) AS VARCHAR(64))                         AS ORDER_ID,
    CAST(TO_NUMBER(TRIM(POS)) AS NUMBER(9, 0))                         AS LINE_NUMBER,
    CAST(UPPER(TRIM(ARTICLE)) AS VARCHAR(64))                          AS SKU,
    CAST(QTY_N AS NUMBER(9, 0))                                        AS QUANTITY,
    PRICE_N                                                            AS UNIT_PRICE,
    DISC_N                                                             AS DISCOUNT_PCT,
    CAST(ROUND(QTY_N * PRICE_N * (1 - DISC_N / 100), 2) AS NUMBER(18, 2)) AS NET_AMOUNT,
    CAST(CASE
        WHEN LOWER(TRIM(STATUS)) IN ('placed', 'new', 'open', 'ordered') THEN 'PLACED'
        WHEN LOWER(TRIM(STATUS)) IN ('shipped', 'sent', 'dispatched') THEN 'SHIPPED'
        WHEN LOWER(TRIM(STATUS)) IN ('cancelled', 'canceled', 'void') THEN 'CANCELLED'
        WHEN LOWER(TRIM(STATUS)) IN ('returned', 'refunded') THEN 'RETURNED'
    END AS VARCHAR(16))                                                AS LINE_STATUS,
    CAST(REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$') AS VARCHAR(255))        AS SOURCE_FILE,
    CONVERT_TIMEZONE('UTC', LOADED_TZ)::timestamp_ntz                  AS LOADED_AT_UTC
FROM latest
