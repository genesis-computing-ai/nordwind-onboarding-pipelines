-- depends_on: {{ ref('customers') }}
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'order_id'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    full_refresh=(false if target.name == 'prod' else none),
    on_schema_change='fail'
) }}

-- Mapping: mapping_ORDERS.sql as the owner approved it (mission repo, commit f1a0aab), orders_raw bound to bronze;
-- the owner's time zone (Q1) is the project variable source_time_zone.
WITH orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'orders_raw') }}
),
latest AS (
    -- [High] one row per order: the order export holds an order once per line
    -- [Medium] ASSUMPTION A3: the order's details come from the newest file that sent a line of it,
    --          from its lowest line position (0 of 186 orders disagree across lines today)
    -- [Medium] ASSUMPTION A2: ties on the file date are broken by load time, then file name
    SELECT *
    FROM orders_raw
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(ORDER_NO))
        ORDER BY TRY_TO_DATE(REGEXP_SUBSTR(_SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}')) DESC NULLS LAST,
                 _LOADED_AT::TIMESTAMP_TZ DESC,
                 _SOURCE_FILE DESC,
                 TRY_TO_NUMBER(TRIM(POS)) ASC NULLS LAST
    ) = 1
)
SELECT
    CAST('{{ var("source_name") }}' AS VARCHAR(64)) AS SOURCE_NAME,            -- [High] kickoff source_name
    CAST(UPPER(TRIM(ORDER_NO)) AS VARCHAR(64)) AS ORDER_ID,                   -- [High] section 5: trimmed, upper-cased
    CAST(NULLIF(UPPER(TRIM(CUSTOMER)), '') AS VARCHAR(64)) AS CUSTOMER_ID,    -- [High] refers to CUSTOMERS, stored by its key rule; NULL for a guest checkout
    CONVERT_TIMEZONE('{{ var("source_time_zone") }}', 'UTC',
        TRY_TO_TIMESTAMP_NTZ(TRIM(CREATED), 'YYYY-MM-DD HH24:MI:SS')) AS ORDERED_AT_UTC, -- [High] owner Q1: local time -> UTC; A4 for the autumn repeated hour
    TO_DATE(TRY_TO_TIMESTAMP_NTZ(TRIM(CREATED), 'YYYY-MM-DD HH24:MI:SS')) AS ORDER_DATE, -- [High] section 5: the local calendar day
    CAST(UPPER(TRIM(CUR)) AS VARCHAR(3)) AS CURRENCY_CODE,                    -- [High] section 5: ISO 4217, upper case
    CAST(CASE
        WHEN LOWER(TRIM(SHIP_TO)) IN ('de', 'germany', 'deutschland') THEN 'DE'
        WHEN LOWER(TRIM(SHIP_TO)) IN ('at', 'austria', 'österreich') THEN 'AT'
        WHEN LOWER(TRIM(SHIP_TO)) IN ('ch', 'switzerland', 'schweiz') THEN 'CH'
    END AS VARCHAR(2)) AS SHIP_COUNTRY,                                        -- [High] section 7 Countries; NULL when none; A1 for an unknown name
    CAST(REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$') AS VARCHAR(255)) AS SOURCE_FILE, -- [High] newest file that sent a line of the order
    CONVERT_TIMEZONE('UTC', _LOADED_AT::TIMESTAMP_TZ)::TIMESTAMP_NTZ AS LOADED_AT_UTC -- [High] load time, UTC
FROM latest
