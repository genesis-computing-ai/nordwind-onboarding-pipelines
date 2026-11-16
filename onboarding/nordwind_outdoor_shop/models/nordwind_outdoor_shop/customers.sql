{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'customer_id'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none)
) }}
-- Approved mapping: mapping_CUSTOMERS.sql (mission repo, commit 01bcefd), customers_raw bound to bronze.
-- This first model carries the bronze load of every feed (pre_hooks in models/schema.yml).
WITH customers_raw AS (
    SELECT CUSTOMER, REGISTERED, TYPE, CITY, COUNTRY, NEWSLETTER, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'customers_raw') }}
),
ranked AS (
    SELECT r.*,
           REGEXP_SUBSTR(r._SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}') AS FILE_DATE,
           r._LOADED_AT::timestamp_tz AS LOADED_TZ
    FROM customers_raw r
),
latest AS (
    SELECT * FROM ranked
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(CUSTOMER))
                               ORDER BY FILE_DATE DESC, LOADED_TZ DESC, _SOURCE_FILE DESC) = 1
)
SELECT
    CAST('nordwind_outdoor_shop' AS VARCHAR(64))                       AS SOURCE_NAME,
    CAST(UPPER(TRIM(CUSTOMER)) AS VARCHAR(64))                         AS CUSTOMER_ID,
    CAST(CASE
        WHEN LOWER(TRIM(TYPE)) IN ('privat', 'privatkunde', 'private', 'consumer') THEN 'CONSUMER'
        WHEN LOWER(TRIM(TYPE)) IN ('firma', 'gewerbe', 'business', 'company') THEN 'BUSINESS'
    END AS VARCHAR(16))                                                AS CUSTOMER_TYPE,
    CAST(NULLIF(TRIM(CITY), '') AS VARCHAR(100))                       AS CITY,
    CAST(CASE
        WHEN NULLIF(TRIM(COUNTRY), '') IS NULL THEN NULL
        WHEN UPPER(TRIM(COUNTRY)) IN ('DE', 'GERMANY', 'DEUTSCHLAND') THEN 'DE'
        WHEN UPPER(TRIM(COUNTRY)) IN ('AT', 'AUSTRIA', 'ÖSTERREICH') THEN 'AT'
        WHEN UPPER(TRIM(COUNTRY)) IN ('CH', 'SWITZERLAND', 'SCHWEIZ') THEN 'CH'
        WHEN REGEXP_LIKE(TRIM(COUNTRY), '^[A-Za-z]{2}$') THEN UPPER(TRIM(COUNTRY))
    END AS VARCHAR(2))                                                 AS COUNTRY_CODE,
    TO_DATE(TRIM(REGISTERED), 'DD.MM.YYYY')                            AS REGISTERED_ON,
    CASE
        WHEN LOWER(TRIM(NEWSLETTER)) IN ('ja', 'j', 'yes', 'y', 'true', '1') THEN TRUE
        WHEN LOWER(TRIM(NEWSLETTER)) IN ('nein', 'n', 'no', 'false', '0') THEN FALSE
    END                                                                AS NEWSLETTER_OPT_IN,
    CAST(REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$') AS VARCHAR(255))        AS SOURCE_FILE,
    CONVERT_TIMEZONE('UTC', LOADED_TZ)::timestamp_ntz                  AS LOADED_AT_UTC
FROM latest
