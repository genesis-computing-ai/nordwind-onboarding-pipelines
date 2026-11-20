{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['order_no', 'source_name'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=false,
    pre_hook=[
        "{{ rehearsal_create_raw_schema() }}",
        "{{ rehearsal_create_raw_table() }}",
        "{{ rehearsal_copy_fixture() }}",
    ],
) }}

-- Mapping: synthetic Nordwind order feed -> this rehearsal's ORDERS table.
WITH nordwind_orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'nordwind_orders_raw') }}
),
latest AS (
    SELECT *, REGEXP_SUBSTR(_SOURCE_FILE, '\\d{4}-\\d{2}-\\d{2}') AS file_date
    FROM nordwind_orders_raw
)
SELECT
    -- [High] order number, trimmed; 186 distinct, unique per order
    TRIM(ORDER_NO)::VARCHAR(20) AS ORDER_NO,
    -- [High] CREATED is German local time without zone (owner decision 1), converted to UTC
    CONVERT_TIMEZONE('{{ var("source_time_zone") }}', 'UTC', TO_TIMESTAMP_NTZ(CREATED, 'YYYY-MM-DD HH24:MI:SS')) AS ORDER_CREATED_AT_UTC,
    -- [Medium] ASSUMPTION A3: a blank customer is an order with no customer number (guest), kept as NULL
    NULLIF(TRIM(CUSTOMER), '')::VARCHAR(20) AS CUSTOMER_ID,
    -- [High] 8 spellings collapse to ISO 3166-1 alpha-2 (DE, AT, CH); an unknown spelling yields NULL
    (CASE UPPER(TRIM(SHIP_TO))
        WHEN 'DE' THEN 'DE' WHEN 'DEUTSCHLAND' THEN 'DE' WHEN 'GERMANY' THEN 'DE'
        WHEN 'AT' THEN 'AT' WHEN 'ÖSTERREICH' THEN 'AT' WHEN 'AUSTRIA' THEN 'AT'
        WHEN 'CH' THEN 'CH' WHEN 'SCHWEIZ' THEN 'CH' WHEN 'SWITZERLAND' THEN 'CH'
     END)::VARCHAR(2) AS SHIP_TO_COUNTRY_CODE,
    -- [High] ISO 4217, upper-cased (EUR / eur -> EUR)
    UPPER(TRIM(CUR))::VARCHAR(3) AS CURRENCY_CODE,
    -- [High] export stamp carries its zone (Z); stored in UTC
    CONVERT_TIMEZONE('UTC', TO_TIMESTAMP_TZ(EXPORTED_AT))::TIMESTAMP_NTZ AS EXPORTED_AT_UTC,
    -- [High] kickoff source_name
    '{{ var("source_name") }}'::VARCHAR(50) AS SOURCE_NAME,
    -- [High] file name only: text after the last /
    REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$')::VARCHAR(200) AS SOURCE_FILE,
    -- [High] load time; one cast reads the snapshot's ISO text and bronze's timestamp
    _LOADED_AT::TIMESTAMP_TZ AS LOADED_AT
FROM latest
-- [Medium] ASSUMPTION A4: an order resent in a later file takes the newest file's header (by the date in the file name)
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRIM(ORDER_NO) ORDER BY file_date DESC, _LOADED_AT::TIMESTAMP_TZ DESC, TRY_TO_NUMBER(TRIM(POS))) = 1
