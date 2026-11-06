{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'order_id', 'line_number'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none),
    pre_hook=[
        "create schema if not exists {{ target.database }}.NORDWIND_OUTDOOR_LIVE_BRONZE",
        "{% if flags.FULL_REFRESH and target.name != 'prod' %}create or replace table{% else %}create table if not exists{% endif %} {{ target.database }}.NORDWIND_OUTDOOR_LIVE_BRONZE.NORDWIND_ORDERS_RAW (order_no varchar, pos varchar, created varchar, customer varchar, article varchar, qty varchar, price varchar, discount varchar, cur varchar, status varchar, ship_to varchar, exported_at varchar, _source_file varchar, _file_row_number number, _loaded_at timestamp_ltz default current_timestamp())",
        "copy into {{ target.database }}.NORDWIND_OUTDOOR_LIVE_BRONZE.NORDWIND_ORDERS_RAW (order_no, pos, created, customer, article, qty, price, discount, cur, status, ship_to, exported_at, _source_file, _file_row_number) from (select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, metadata$filename, metadata$file_row_number from @{{ target.database ~ '.' ~ var('prod_drop_stage') if target.name == 'prod' else var('drop_stage') }}) pattern = '{{ var('file_pattern') }}' file_format = (format_name = '{{ target.database }}.{{ var('file_format') }}') force = {{ 'true' if (flags.FULL_REFRESH and target.name != 'prod') else 'false' }}",
    ],
) }}

-- Mapping approved by the owner (mission repo mapping_ORDER_LINE.sql at dae8ccd), run over bronze.
-- The only changes from the approved SQL: the nordwind_orders_raw CTE reads the bronze table, and the
-- source time zone and source_name are read from project variables instead of literals.
WITH nordwind_orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO,
           _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'nordwind_orders_raw') }}
),
prepared AS (
    SELECT
        r.*,
        REGEXP_SUBSTR(r._SOURCE_FILE, '[^/]+$')                                   AS file_name,
        TRY_TO_DATE(REGEXP_SUBSTR(r._SOURCE_FILE, '\\d{4}-\\d{2}-\\d{2}'), 'YYYY-MM-DD') AS file_date,
        TO_TIMESTAMP_NTZ(TRIM(r.CREATED), 'YYYY-MM-DD HH24:MI:SS')               AS created_local,
        TRY_TO_NUMBER(REPLACE(REPLACE(TRIM(r.PRICE), '.', ''), ',', '.'), 18, 2)  AS unit_price,
        COALESCE(TRY_TO_NUMBER(NULLIF(REPLACE(REPLACE(TRIM(r.DISCOUNT), '%', ''), ' ', ''), ''), 5, 2), 0) AS discount_pct,
        TRY_TO_NUMBER(TRIM(r.QTY), 9, 0)                                          AS quantity
    FROM nordwind_orders_raw r
),
latest AS (
    -- Key SOURCE_NAME, ORDER_ID, LINE_NUMBER; a later file's values replace earlier ones.
    SELECT *
    FROM prepared
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(ORDER_NO)), TRY_TO_NUMBER(TRIM(POS), 9, 0)
        ORDER BY file_date DESC, _LOADED_AT::TIMESTAMP_TZ DESC) = 1
)
SELECT
    CAST('{{ var("source_name") }}' AS VARCHAR(64))                                AS SOURCE_NAME,
    CAST(UPPER(TRIM(ORDER_NO)) AS VARCHAR(64))                                    AS ORDER_ID,
    CAST(TRY_TO_NUMBER(TRIM(POS), 9, 0) AS NUMBER(9,0))                           AS LINE_NUMBER,
    CAST(CONVERT_TIMEZONE('{{ var("source_time_zone") }}', 'UTC', created_local) AS TIMESTAMP_NTZ) AS ORDERED_AT_UTC,
    CAST(created_local AS DATE)                                                   AS ORDER_DATE,
    CAST(NULLIF(TRIM(CUSTOMER), '') AS VARCHAR(64))                               AS CUSTOMER_REF,
    CAST(UPPER(TRIM(ARTICLE)) AS VARCHAR(64))                                     AS SKU,
    CAST(quantity AS NUMBER(9,0))                                                 AS QUANTITY,
    CAST(unit_price AS NUMBER(18,2))                                              AS UNIT_PRICE,
    CAST(discount_pct AS NUMBER(5,2))                                             AS DISCOUNT_PCT,
    CAST(ROUND(quantity * unit_price * (1 - discount_pct / 100), 2) AS NUMBER(18,2)) AS NET_AMOUNT,
    CAST(UPPER(TRIM(CUR)) AS VARCHAR(3))                                          AS CURRENCY_CODE,
    CAST(CASE
        WHEN LOWER(TRIM(STATUS)) IN ('placed', 'new', 'open', 'ordered')     THEN 'PLACED'
        WHEN LOWER(TRIM(STATUS)) IN ('shipped', 'sent', 'dispatched')        THEN 'SHIPPED'
        WHEN LOWER(TRIM(STATUS)) IN ('cancelled', 'canceled', 'void')        THEN 'CANCELLED'
        WHEN LOWER(TRIM(STATUS)) IN ('returned', 'refunded')                 THEN 'RETURNED'
        ELSE NULL END AS VARCHAR(16))                                             AS LINE_STATUS,
    CAST(CASE
        WHEN LOWER(TRIM(SHIP_TO)) IN ('de', 'germany', 'deutschland')        THEN 'DE'
        WHEN LOWER(TRIM(SHIP_TO)) IN ('at', 'austria', 'österreich')         THEN 'AT'
        WHEN LOWER(TRIM(SHIP_TO)) IN ('ch', 'switzerland', 'schweiz')        THEN 'CH'
        WHEN REGEXP_LIKE(TRIM(SHIP_TO), '[A-Za-z]{2}')                       THEN UPPER(TRIM(SHIP_TO))
        ELSE NULL END AS VARCHAR(2))                                              AS SHIP_COUNTRY,
    CAST(file_name AS VARCHAR(255))                                               AS SOURCE_FILE,
    CAST(CONVERT_TIMEZONE('UTC', _LOADED_AT::TIMESTAMP_TZ) AS TIMESTAMP_NTZ)      AS LOADED_AT_UTC
FROM latest
