-- depends_on: {{ ref('customers') }}
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'order_id'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none)
) }}
-- Approved mapping: mapping_ORDERS.sql (mission repo, commit 01bcefd), orders_raw bound to bronze;
-- the source time zone is the project variable source_time_zone (owner decision 1).
WITH orders_raw AS (
    SELECT ORDER_NO, POS, CREATED, CUSTOMER, ARTICLE, QTY, PRICE, DISCOUNT, CUR, STATUS, SHIP_TO, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'orders_raw') }}
),
ranked AS (
    SELECT r.*,
           REGEXP_SUBSTR(r._SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}') AS FILE_DATE,
           r._LOADED_AT::timestamp_tz AS LOADED_TZ,
           TO_TIMESTAMP_NTZ(TRIM(r.CREATED), 'YYYY-MM-DD HH24:MI:SS') AS CREATED_LOCAL
    FROM orders_raw r
),
latest AS (
    SELECT * FROM ranked
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(ORDER_NO))
                               ORDER BY FILE_DATE DESC, LOADED_TZ DESC, _SOURCE_FILE DESC, TRY_TO_NUMBER(TRIM(POS)) ASC) = 1
)
SELECT
    CAST('nordwind_outdoor_shop' AS VARCHAR(64))                       AS SOURCE_NAME,
    CAST(UPPER(TRIM(ORDER_NO)) AS VARCHAR(64))                         AS ORDER_ID,
    CAST(NULLIF(UPPER(TRIM(CUSTOMER)), '') AS VARCHAR(64))             AS CUSTOMER_ID,
    CONVERT_TIMEZONE('{{ var("source_time_zone") }}', 'UTC', CREATED_LOCAL) AS ORDERED_AT_UTC,
    TO_DATE(CREATED_LOCAL)                                             AS ORDER_DATE,
    CAST(UPPER(TRIM(CUR)) AS VARCHAR(3))                               AS CURRENCY_CODE,
    CAST(CASE
        WHEN NULLIF(TRIM(SHIP_TO), '') IS NULL THEN NULL
        WHEN UPPER(TRIM(SHIP_TO)) IN ('DE', 'GERMANY', 'DEUTSCHLAND') THEN 'DE'
        WHEN UPPER(TRIM(SHIP_TO)) IN ('AT', 'AUSTRIA', 'ÖSTERREICH') THEN 'AT'
        WHEN UPPER(TRIM(SHIP_TO)) IN ('CH', 'SWITZERLAND', 'SCHWEIZ') THEN 'CH'
        WHEN REGEXP_LIKE(TRIM(SHIP_TO), '^[A-Za-z]{2}$') THEN UPPER(TRIM(SHIP_TO))
    END AS VARCHAR(2))                                                 AS SHIP_COUNTRY,
    CAST(REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$') AS VARCHAR(255))        AS SOURCE_FILE,
    CONVERT_TIMEZONE('UTC', LOADED_TZ)::timestamp_ntz                  AS LOADED_AT_UTC
FROM latest
