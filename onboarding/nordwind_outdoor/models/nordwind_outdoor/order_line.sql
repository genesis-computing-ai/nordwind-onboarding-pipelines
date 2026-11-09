{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'order_id', 'line_number'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none),
    pre_hook=[
        "create schema if not exists {{ target.database }}.NORDWIND_OUTDOOR_BRONZE",
        "{% if flags.FULL_REFRESH and target.name != 'prod' %}create or replace table{% else %}create table if not exists{% endif %} {{ target.database }}.NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW (order_no varchar, pos varchar, created varchar, customer varchar, article varchar, qty varchar, price varchar, discount varchar, cur varchar, status varchar, ship_to varchar, exported_at varchar, _source_file varchar, _file_row_number number, _loaded_at timestamp_ltz default current_timestamp())",
        "copy into {{ target.database }}.NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW (order_no, pos, created, customer, article, qty, price, discount, cur, status, ship_to, exported_at, _source_file, _file_row_number) from (select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, metadata$filename, metadata$file_row_number from @{{ (target.database ~ '.' ~ var('prod_drop_stage')) if target.name == 'prod' else var('drop_stage') }}) pattern = '{{ var('file_pattern') }}' file_format = (format_name = '{{ target.database }}.{{ var('file_format') }}') force = {{ 'true' if (flags.FULL_REFRESH and target.name != 'prod') else 'false' }}",
    ],
) }}

-- ORDER_LINE: the approved mapping SQL (mission repo mapping_ORDER_LINE.sql, approved at ee991ac).
-- Bound to bronze: the nordwind_orders_raw CTE reads the bronze table; the owner's time zone and the
-- source name are read through project variables instead of literals. Nothing else differs.

WITH nordwind_orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'nordwind_orders_raw') }}
),

mapped AS (
    SELECT
        '{{ var("source_name") }}'::VARCHAR(64)                                                 AS SOURCE_NAME,
        UPPER(TRIM(ORDER_NO))::VARCHAR(64)                                                      AS ORDER_ID,
        TO_NUMBER(TRIM(POS), 9, 0)                                                              AS LINE_NUMBER,
        CONVERT_TIMEZONE('{{ var("source_time_zone") }}', 'UTC',
            TO_TIMESTAMP_NTZ(TRIM(CREATED), 'YYYY-MM-DD HH24:MI:SS'))::TIMESTAMP_NTZ             AS ORDERED_AT_UTC,
        TO_DATE(TO_TIMESTAMP_NTZ(TRIM(CREATED), 'YYYY-MM-DD HH24:MI:SS'))                       AS ORDER_DATE,
        NULLIF(TRIM(CUSTOMER), '')::VARCHAR(64)                                                 AS CUSTOMER_REF,
        UPPER(TRIM(ARTICLE))::VARCHAR(64)                                                       AS SKU,
        TO_NUMBER(TRIM(QTY), 9, 0)                                                              AS QUANTITY,
        TO_NUMBER(REPLACE(REPLACE(TRIM(PRICE), '.', ''), ',', '.'), 18, 2)                      AS UNIT_PRICE,
        COALESCE(TO_NUMBER(NULLIF(REPLACE(REPLACE(TRIM(DISCOUNT), '%', ''), ' ', ''), ''), 5, 2), 0)::NUMBER(5,2)
                                                                                                AS DISCOUNT_PCT,
        UPPER(TRIM(CUR))::VARCHAR(3)                                                            AS CURRENCY_CODE,
        (CASE WHEN LOWER(TRIM(STATUS)) IN ('placed','new','open','ordered')   THEN 'PLACED'
              WHEN LOWER(TRIM(STATUS)) IN ('shipped','sent','dispatched')     THEN 'SHIPPED'
              WHEN LOWER(TRIM(STATUS)) IN ('cancelled','canceled','void')     THEN 'CANCELLED'
              WHEN LOWER(TRIM(STATUS)) IN ('returned','refunded')             THEN 'RETURNED'
         END)::VARCHAR(16)                                                                      AS LINE_STATUS,
        (CASE WHEN NULLIF(TRIM(SHIP_TO), '') IS NULL                                  THEN NULL
              WHEN LOWER(TRIM(SHIP_TO)) IN ('de','germany','deutschland')             THEN 'DE'
              WHEN LOWER(TRIM(SHIP_TO)) IN ('at','austria','österreich')              THEN 'AT'
              WHEN LOWER(TRIM(SHIP_TO)) IN ('ch','switzerland','schweiz')             THEN 'CH'
         END)::VARCHAR(2)                                                                       AS SHIP_COUNTRY,
        REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$')::VARCHAR(255)                                     AS SOURCE_FILE,
        CONVERT_TIMEZONE('UTC', _LOADED_AT::TIMESTAMP_TZ)::TIMESTAMP_NTZ                        AS LOADED_AT_UTC,
        TO_DATE(REGEXP_SUBSTR(_SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}'), 'YYYY-MM-DD')        AS _FILE_DATE
    FROM nordwind_orders_raw
)

SELECT
    SOURCE_NAME::VARCHAR(64)                                                                    AS SOURCE_NAME,
    ORDER_ID::VARCHAR(64)                                                                       AS ORDER_ID,
    LINE_NUMBER::NUMBER(9,0)                                                                    AS LINE_NUMBER,
    ORDERED_AT_UTC::TIMESTAMP_NTZ                                                               AS ORDERED_AT_UTC,
    ORDER_DATE::DATE                                                                            AS ORDER_DATE,
    CUSTOMER_REF::VARCHAR(64)                                                                   AS CUSTOMER_REF,
    SKU::VARCHAR(64)                                                                            AS SKU,
    QUANTITY::NUMBER(9,0)                                                                       AS QUANTITY,
    UNIT_PRICE::NUMBER(18,2)                                                                    AS UNIT_PRICE,
    DISCOUNT_PCT::NUMBER(5,2)                                                                   AS DISCOUNT_PCT,
    ROUND(QUANTITY * UNIT_PRICE * (100 - DISCOUNT_PCT) / 100, 2)::NUMBER(18,2)                  AS NET_AMOUNT,
    CURRENCY_CODE::VARCHAR(3)                                                                   AS CURRENCY_CODE,
    LINE_STATUS::VARCHAR(16)                                                                    AS LINE_STATUS,
    SHIP_COUNTRY::VARCHAR(2)                                                                    AS SHIP_COUNTRY,
    SOURCE_FILE::VARCHAR(255)                                                                   AS SOURCE_FILE,
    LOADED_AT_UTC::TIMESTAMP_NTZ                                                                AS LOADED_AT_UTC
FROM mapped
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SOURCE_NAME, ORDER_ID, LINE_NUMBER
    ORDER BY _FILE_DATE DESC, LOADED_AT_UTC DESC, SOURCE_FILE DESC
) = 1
