{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'order_id', 'line_number'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = 'nordwind_outdoor'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none),
    pre_hook=[
        "create schema if not exists {{ target.database }}.NORDWIND_OUTDOOR_BRONZE",
        "{% if flags.FULL_REFRESH and target.name != 'prod' %}create or replace table{% else %}create table if not exists{% endif %} {{ target.database }}.NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW (order_no varchar, pos varchar, created varchar, customer varchar, article varchar, qty varchar, price varchar, discount varchar, cur varchar, status varchar, ship_to varchar, exported_at varchar, _source_file varchar, _file_row_number number, _loaded_at timestamp_ltz default current_timestamp())",
        "copy into {{ target.database }}.NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW (order_no, pos, created, customer, article, qty, price, discount, cur, status, ship_to, exported_at, _source_file, _file_row_number) from (select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, metadata$filename, metadata$file_row_number from @{{ var('drop_stage') }}) pattern = '{{ var('file_pattern') }}' file_format = (format_name = '{{ target.database }}.{{ var('file_format') }}') force = {% if flags.FULL_REFRESH and target.name != 'prod' %}true{% else %}false{% endif %}",
    ],
) }}

-- The approved mapping (mission repo mapping_ORDER_LINE.sql at af48552) with two changes only:
-- the nordwind_orders_raw CTE reads this pipeline's bronze table, and the owner's time zone is the
-- project variable source_time_zone. The outer SELECT casts to the standard's types for the contract.
WITH nordwind_orders_raw AS (
  SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
  FROM {{ source('bronze', 'nordwind_orders_raw') }}
),
mapped AS (
  SELECT
    'nordwind_outdoor'                                                         AS SOURCE_NAME,
    UPPER(TRIM(ORDER_NO))                                                      AS ORDER_ID,
    TO_NUMBER(TRIM(POS))                                                       AS LINE_NUMBER,
    CONVERT_TIMEZONE('{{ var("source_time_zone") }}', 'UTC',
      TO_TIMESTAMP_NTZ(TRIM(CREATED), 'YYYY-MM-DD HH24:MI:SS'))                AS ORDERED_AT_UTC,
    TO_DATE(TO_TIMESTAMP_NTZ(TRIM(CREATED), 'YYYY-MM-DD HH24:MI:SS'))          AS ORDER_DATE,
    NULLIF(TRIM(CUSTOMER), '')                                                 AS CUSTOMER_REF,
    UPPER(TRIM(ARTICLE))                                                       AS SKU,
    TO_NUMBER(TRIM(QTY))                                                       AS QUANTITY,
    TO_NUMBER(REPLACE(REPLACE(TRIM(PRICE), '.', ''), ',', '.'), 12, 2)         AS UNIT_PRICE,
    COALESCE(TO_NUMBER(NULLIF(REPLACE(REPLACE(TRIM(DISCOUNT), '%', ''), ' ', ''), ''), 5, 2), 0)
                                                                               AS DISCOUNT_PCT,
    UPPER(TRIM(CUR))                                                           AS CURRENCY_CODE,
    CASE UPPER(TRIM(STATUS)) WHEN 'CANCELED' THEN 'CANCELLED'
         ELSE UPPER(TRIM(STATUS)) END                                          AS LINE_STATUS,
    CASE UPPER(TRIM(SHIP_TO))
      WHEN 'DE' THEN 'DE' WHEN 'GERMANY' THEN 'DE' WHEN 'DEUTSCHLAND' THEN 'DE'
      WHEN 'AT' THEN 'AT' WHEN 'AUSTRIA' THEN 'AT' WHEN 'ÖSTERREICH' THEN 'AT'
      WHEN 'CH' THEN 'CH' WHEN 'SWITZERLAND' THEN 'CH' WHEN 'SCHWEIZ' THEN 'CH'
      ELSE NULL END                                                            AS SHIP_COUNTRY,
    REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$')                                      AS SOURCE_FILE,
    CONVERT_TIMEZONE('UTC', _LOADED_AT::TIMESTAMP_TZ)::TIMESTAMP_NTZ          AS LOADED_AT_UTC,
    TO_DATE(REGEXP_SUBSTR(REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$'), '[0-9]{4}-[0-9]{2}-[0-9]{2}')) AS _FILE_DATE,
    TRY_TO_TIMESTAMP_TZ(EXPORTED_AT)                                           AS _EXPORTED_AT
  FROM nordwind_orders_raw
),
standard_rows AS (
  SELECT
    SOURCE_NAME, ORDER_ID, LINE_NUMBER, ORDERED_AT_UTC, ORDER_DATE, CUSTOMER_REF, SKU, QUANTITY,
    UNIT_PRICE, DISCOUNT_PCT,
    ROUND(QUANTITY * UNIT_PRICE * (1 - DISCOUNT_PCT / 100), 2)                 AS NET_AMOUNT,
    CURRENCY_CODE, LINE_STATUS, SHIP_COUNTRY, SOURCE_FILE, LOADED_AT_UTC
  FROM mapped
  QUALIFY ROW_NUMBER() OVER (PARTITION BY SOURCE_NAME, ORDER_ID, LINE_NUMBER
                             ORDER BY _FILE_DATE DESC, _EXPORTED_AT DESC NULLS LAST, LOADED_AT_UTC DESC) = 1
)
SELECT
  SOURCE_NAME::varchar(64)     AS source_name,
  ORDER_ID::varchar(64)        AS order_id,
  LINE_NUMBER::number(9,0)     AS line_number,
  ORDERED_AT_UTC::timestamp_ntz AS ordered_at_utc,
  ORDER_DATE::date             AS order_date,
  CUSTOMER_REF::varchar(64)    AS customer_ref,
  SKU::varchar(64)             AS sku,
  QUANTITY::number(9,0)        AS quantity,
  UNIT_PRICE::number(18,2)     AS unit_price,
  DISCOUNT_PCT::number(5,2)    AS discount_pct,
  NET_AMOUNT::number(18,2)     AS net_amount,
  CURRENCY_CODE::varchar(3)    AS currency_code,
  LINE_STATUS::varchar(16)     AS line_status,
  SHIP_COUNTRY::varchar(2)     AS ship_country,
  SOURCE_FILE::varchar(255)    AS source_file,
  LOADED_AT_UTC::timestamp_ntz AS loaded_at_utc
FROM standard_rows
