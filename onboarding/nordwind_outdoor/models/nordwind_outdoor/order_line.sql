{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'order_id', 'line_number'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none),
    pre_hook=[
        "create schema if not exists {{ target.database }}.NORDWIND_OUTDOOR_BRONZE",
        "{{ 'create or replace table' if (flags.FULL_REFRESH and target.name != 'prod') else 'create table if not exists' }} {{ target.database }}.NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW (order_no varchar, pos varchar, created varchar, customer varchar, article varchar, qty varchar, price varchar, discount varchar, cur varchar, status varchar, ship_to varchar, exported_at varchar, _source_file varchar, _file_row_number number, _loaded_at timestamp_ltz default current_timestamp())",
        "copy into {{ target.database }}.NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW (order_no, pos, created, customer, article, qty, price, discount, cur, status, ship_to, exported_at, _source_file, _file_row_number) from (select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, metadata$filename, metadata$file_row_number from @{{ target.database ~ '.' ~ var('prod_drop_stage') if target.name == 'prod' else var('drop_stage') }}) pattern = '{{ var('file_pattern') }}' file_format = (format_name = '{{ target.database }}.{{ var('file_format') }}') force = {{ 'true' if (flags.FULL_REFRESH and target.name != 'prod') else 'false' }}",
    ],
) }}

-- The committed mapping SQL (mapping_ORDER_LINE.sql, approved at mission-repo commit 8c56819) with the
-- nordwind_orders_raw CTE reading the bronze table, and the two owner decisions read from project variables.
WITH nordwind_orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO,
           _source_file, _loaded_at
    FROM {{ source('bronze', 'nordwind_orders_raw') }}
),
parsed AS (
    SELECT
        UPPER(TRIM(ORDER_NO))                                              AS order_id,
        TRIM(POS)::NUMBER(9,0)                                             AS line_number,
        TO_TIMESTAMP_NTZ(TRIM(CREATED), 'YYYY-MM-DD HH24:MI:SS')           AS created_local,
        NULLIF(TRIM(CUSTOMER), '')                                         AS customer_ref,
        UPPER(TRIM(ARTICLE))                                               AS sku,
        TRIM(QTY)::NUMBER(9,0)                                             AS quantity,
        REPLACE(REPLACE(TRIM(PRICE), '.', ''), ',', '.')::NUMBER(18,2)     AS unit_price,
        COALESCE(NULLIF(TRIM(REPLACE(DISCOUNT, '%', '')), ''), '0')::NUMBER(5,2) AS discount_pct,
        UPPER(TRIM(CUR))                                                   AS currency_code,
        UPPER(TRIM(STATUS))                                                AS status_in,
        UPPER(TRIM(SHIP_TO))                                               AS ship_in,
        REGEXP_SUBSTR(_source_file, '[^/]+$')                              AS source_file,
        _loaded_at::TIMESTAMP_TZ                                           AS loaded_at_tz
    FROM nordwind_orders_raw
),
mapped AS (
    SELECT
        '{{ var("source_name") }}'::VARCHAR(64)                            AS SOURCE_NAME,
        order_id::VARCHAR(64)                                              AS ORDER_ID,
        line_number                                                        AS LINE_NUMBER,
        CONVERT_TIMEZONE('{{ var("source_time_zone") }}', 'UTC', created_local)::TIMESTAMP_NTZ AS ORDERED_AT_UTC,
        created_local::DATE                                                AS ORDER_DATE,
        customer_ref::VARCHAR(64)                                          AS CUSTOMER_REF,
        sku::VARCHAR(64)                                                   AS SKU,
        quantity                                                           AS QUANTITY,
        unit_price                                                         AS UNIT_PRICE,
        discount_pct                                                       AS DISCOUNT_PCT,
        ROUND(quantity * unit_price * (1 - discount_pct / 100), 2)::NUMBER(18,2) AS NET_AMOUNT,
        currency_code::VARCHAR(3)                                          AS CURRENCY_CODE,
        CASE
            WHEN status_in IN ('PLACED', 'NEW', 'OPEN', 'ORDERED')        THEN 'PLACED'
            WHEN status_in IN ('SHIPPED', 'SENT', 'DISPATCHED')            THEN 'SHIPPED'
            WHEN status_in IN ('CANCELLED', 'CANCELED', 'VOID')            THEN 'CANCELLED'
            WHEN status_in IN ('RETURNED', 'REFUNDED')                     THEN 'RETURNED'
        END::VARCHAR(16)                                                   AS LINE_STATUS,
        CASE
            WHEN ship_in IS NULL OR ship_in = ''                           THEN NULL
            WHEN ship_in IN ('DE', 'GERMANY', 'DEUTSCHLAND')               THEN 'DE'
            WHEN ship_in IN ('AT', 'AUSTRIA', 'ÖSTERREICH')                THEN 'AT'
            WHEN ship_in IN ('CH', 'SWITZERLAND', 'SCHWEIZ')               THEN 'CH'
            WHEN REGEXP_LIKE(ship_in, '[A-Z]{2}')                          THEN ship_in
        END::VARCHAR(2)                                                    AS SHIP_COUNTRY,
        source_file::VARCHAR(255)                                          AS SOURCE_FILE,
        CONVERT_TIMEZONE('UTC', loaded_at_tz)::TIMESTAMP_NTZ               AS LOADED_AT_UTC,
        TRY_TO_DATE(REGEXP_SUBSTR(source_file, '\\d{4}-\\d{2}-\\d{2}'), 'YYYY-MM-DD') AS _file_date,
        loaded_at_tz                                                       AS _loaded_at_tz
    FROM parsed
)
SELECT
    SOURCE_NAME, ORDER_ID, LINE_NUMBER, ORDERED_AT_UTC, ORDER_DATE, CUSTOMER_REF, SKU, QUANTITY,
    UNIT_PRICE, DISCOUNT_PCT, NET_AMOUNT, CURRENCY_CODE, LINE_STATUS, SHIP_COUNTRY, SOURCE_FILE, LOADED_AT_UTC
FROM mapped
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY SOURCE_NAME, ORDER_ID, LINE_NUMBER
    ORDER BY _file_date DESC NULLS LAST, _loaded_at_tz DESC
) = 1
