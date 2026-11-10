{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['SOURCE_NAME', 'ORDER_ID', 'LINE_NUMBER'],
    incremental_predicates=["DBT_INTERNAL_DEST.SOURCE_NAME = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none),
    pre_hook=[
        "create schema if not exists {{ target.database }}.NORDWIND_OUTDOOR_2_BRONZE",
        "create {{ 'or replace' if (flags.FULL_REFRESH and target.name != 'prod') else '' }} table {{ '' if (flags.FULL_REFRESH and target.name != 'prod') else 'if not exists' }} {{ target.database }}.NORDWIND_OUTDOOR_2_BRONZE.NORDWIND_ORDERS_RAW (ORDER_NO varchar, POS varchar, CREATED varchar, CUSTOMER varchar, ARTICLE varchar, QTY varchar, PRICE varchar, DISCOUNT varchar, CUR varchar, STATUS varchar, SHIP_TO varchar, EXPORTED_AT varchar, _SOURCE_FILE varchar, _FILE_ROW_NUMBER number, _LOADED_AT timestamp_ltz default current_timestamp())",
        "copy into {{ target.database }}.NORDWIND_OUTDOOR_2_BRONZE.NORDWIND_ORDERS_RAW (ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, EXPORTED_AT, _SOURCE_FILE, _FILE_ROW_NUMBER) from (select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, metadata$filename, metadata$file_row_number from @{{ target.database ~ '.' ~ var('prod_drop_stage') if target.name == 'prod' else var('drop_stage') }}) pattern = '{{ var('file_pattern') }}' file_format = (format_name = '{{ target.database }}.{{ var('file_format') }}') force = {{ 'true' if (flags.FULL_REFRESH and target.name != 'prod') else 'false' }}",
    ],
) }}

-- Body: mapping_ORDER_LINE.sql as approved (Mission repo commit 465ca9a), with the nordwind_orders_raw CTE
-- reading the bronze table, and the two owner/kickoff literals read through project variables
-- (source_name -> 'nordwind_outdoor_2', source_time_zone -> 'Europe/Berlin'), which render to the same values.

WITH nordwind_orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO,
           _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'nordwind_orders_raw') }}
),

prepared AS (
    SELECT
        UPPER(TRIM(ORDER_NO))                                                  AS order_id,
        TO_NUMBER(TRIM(POS), 9, 0)                                             AS line_number,
        TO_TIMESTAMP_NTZ(TRIM(CREATED), 'YYYY-MM-DD HH24:MI:SS')               AS created_local,
        NULLIF(TRIM(CUSTOMER), '')                                             AS customer_ref,
        UPPER(TRIM(ARTICLE))                                                   AS sku,
        TO_NUMBER(TRIM(QTY), 9, 0)                                             AS quantity,
        TO_NUMBER(IFF(CONTAINS(TRIM(PRICE), ','),
                      REPLACE(REPLACE(TRIM(PRICE), '.', ''), ',', '.'),
                      TRIM(PRICE)), 18, 2)                                     AS unit_price,
        COALESCE(TO_NUMBER(NULLIF(REPLACE(REPLACE(TRIM(DISCOUNT), '%', ''), ' ', ''), ''), 5, 2), 0)
                                                                               AS discount_pct,
        UPPER(TRIM(CUR))                                                       AS currency_code,
        CASE
            WHEN UPPER(TRIM(STATUS)) IN ('PLACED', 'NEW', 'OPEN', 'ORDERED')     THEN 'PLACED'
            WHEN UPPER(TRIM(STATUS)) IN ('SHIPPED', 'SENT', 'DISPATCHED')        THEN 'SHIPPED'
            WHEN UPPER(TRIM(STATUS)) IN ('CANCELLED', 'CANCELED', 'VOID')        THEN 'CANCELLED'
            WHEN UPPER(TRIM(STATUS)) IN ('RETURNED', 'REFUNDED')                 THEN 'RETURNED'
        END                                                                    AS line_status,
        CASE
            WHEN NULLIF(TRIM(SHIP_TO), '') IS NULL                                THEN NULL
            WHEN UPPER(TRIM(SHIP_TO)) IN ('DE', 'GERMANY', 'DEUTSCHLAND')         THEN 'DE'
            WHEN UPPER(TRIM(SHIP_TO)) IN ('AT', 'AUSTRIA', 'ÖSTERREICH')          THEN 'AT'
            WHEN UPPER(TRIM(SHIP_TO)) IN ('CH', 'SWITZERLAND', 'SCHWEIZ')         THEN 'CH'
            WHEN LENGTH(TRIM(SHIP_TO)) = 2                                         THEN UPPER(TRIM(SHIP_TO))
        END                                                                    AS ship_country,
        REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$')                                  AS source_file,
        CONVERT_TIMEZONE('UTC', _LOADED_AT::TIMESTAMP_TZ)::TIMESTAMP_NTZ       AS loaded_at_utc,
        TO_DATE(REGEXP_SUBSTR(_SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}'))     AS file_date
    FROM nordwind_orders_raw
)

SELECT
    CAST('{{ var("source_name") }}' AS VARCHAR(64))                                       AS SOURCE_NAME,
    CAST(order_id AS VARCHAR(64))                                                         AS ORDER_ID,
    CAST(line_number AS NUMBER(9, 0))                                                     AS LINE_NUMBER,
    CAST(CONVERT_TIMEZONE('{{ var("source_time_zone") }}', 'UTC', created_local) AS TIMESTAMP_NTZ) AS ORDERED_AT_UTC,
    CAST(created_local AS DATE)                                                           AS ORDER_DATE,
    CAST(customer_ref AS VARCHAR(64))                                                     AS CUSTOMER_REF,
    CAST(sku AS VARCHAR(64))                                                              AS SKU,
    CAST(quantity AS NUMBER(9, 0))                                                        AS QUANTITY,
    CAST(unit_price AS NUMBER(18, 2))                                                     AS UNIT_PRICE,
    CAST(discount_pct AS NUMBER(5, 2))                                                    AS DISCOUNT_PCT,
    CAST(ROUND(quantity * unit_price * (1 - discount_pct / 100), 2) AS NUMBER(18, 2))     AS NET_AMOUNT,
    CAST(currency_code AS VARCHAR(3))                                                     AS CURRENCY_CODE,
    CAST(line_status AS VARCHAR(16))                                                      AS LINE_STATUS,
    CAST(ship_country AS VARCHAR(2))                                                      AS SHIP_COUNTRY,
    CAST(source_file AS VARCHAR(255))                                                     AS SOURCE_FILE,
    CAST(loaded_at_utc AS TIMESTAMP_NTZ)                                                  AS LOADED_AT_UTC
FROM prepared
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY order_id, line_number
    ORDER BY file_date DESC, loaded_at_utc DESC, source_file DESC
) = 1
