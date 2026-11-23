{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'customer_id'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    full_refresh=(false if target.name == 'prod' else none),
    on_schema_change='fail',
    pre_hook=[
        "create schema if not exists {{ target.database }}.NORDWIND_OUTDOOR_SHOP_2_BRONZE",
        "{% if flags.FULL_REFRESH and target.name != 'prod' %}create or replace table{% else %}create table if not exists{% endif %} {{ target.database }}.NORDWIND_OUTDOOR_SHOP_2_BRONZE.CUSTOMERS_RAW (customer varchar, registered varchar, type varchar, city varchar, country varchar, newsletter varchar, exported_at varchar, _source_file varchar, _file_row_number number, _loaded_at timestamp_ltz default current_timestamp())",
        "copy into {{ target.database }}.NORDWIND_OUTDOOR_SHOP_2_BRONZE.CUSTOMERS_RAW (customer, registered, type, city, country, newsletter, exported_at, _source_file, _file_row_number) from (select $1, $2, $3, $4, $5, $6, $7, metadata$filename, metadata$file_row_number from @{{ target.database ~ '.' ~ var('prod_drop_stage') if target.name == 'prod' else var('drop_stage') }}) pattern = '{{ var('file_patterns')['customers_raw'] }}' file_format = (format_name = '{{ target.database }}.{{ var('file_format') }}') force = {{ 'true' if (flags.FULL_REFRESH and target.name != 'prod') else 'false' }}",
        "create schema if not exists {{ target.database }}.NORDWIND_OUTDOOR_SHOP_2_BRONZE",
        "{% if flags.FULL_REFRESH and target.name != 'prod' %}create or replace table{% else %}create table if not exists{% endif %} {{ target.database }}.NORDWIND_OUTDOOR_SHOP_2_BRONZE.ARTICLES_RAW (article varchar, name varchar, category varchar, price varchar, cur varchar, active varchar, exported_at varchar, _source_file varchar, _file_row_number number, _loaded_at timestamp_ltz default current_timestamp())",
        "copy into {{ target.database }}.NORDWIND_OUTDOOR_SHOP_2_BRONZE.ARTICLES_RAW (article, name, category, price, cur, active, exported_at, _source_file, _file_row_number) from (select $1, $2, $3, $4, $5, $6, $7, metadata$filename, metadata$file_row_number from @{{ target.database ~ '.' ~ var('prod_drop_stage') if target.name == 'prod' else var('drop_stage') }}) pattern = '{{ var('file_patterns')['articles_raw'] }}' file_format = (format_name = '{{ target.database }}.{{ var('file_format') }}') force = {{ 'true' if (flags.FULL_REFRESH and target.name != 'prod') else 'false' }}",
        "create schema if not exists {{ target.database }}.NORDWIND_OUTDOOR_SHOP_2_BRONZE",
        "{% if flags.FULL_REFRESH and target.name != 'prod' %}create or replace table{% else %}create table if not exists{% endif %} {{ target.database }}.NORDWIND_OUTDOOR_SHOP_2_BRONZE.ORDERS_RAW (order_no varchar, pos varchar, created varchar, customer varchar, article varchar, qty varchar, price varchar, discount varchar, cur varchar, status varchar, ship_to varchar, exported_at varchar, _source_file varchar, _file_row_number number, _loaded_at timestamp_ltz default current_timestamp())",
        "copy into {{ target.database }}.NORDWIND_OUTDOOR_SHOP_2_BRONZE.ORDERS_RAW (order_no, pos, created, customer, article, qty, price, discount, cur, status, ship_to, exported_at, _source_file, _file_row_number) from (select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, metadata$filename, metadata$file_row_number from @{{ target.database ~ '.' ~ var('prod_drop_stage') if target.name == 'prod' else var('drop_stage') }}) pattern = '{{ var('file_patterns')['orders_raw'] }}' file_format = (format_name = '{{ target.database }}.{{ var('file_format') }}') force = {{ 'true' if (flags.FULL_REFRESH and target.name != 'prod') else 'false' }}",
    ],
) }}

-- Mapping: mapping_CUSTOMERS.sql as the owner approved it (mission repo, commit f1a0aab), customers_raw bound to bronze.
WITH customers_raw AS (
    SELECT CUSTOMER, REGISTERED, TYPE, CITY, COUNTRY, NEWSLETTER, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'customers_raw') }}
),
latest AS (
    -- [High] one row per key; the newest file by the date in its name wins (dictionary section 1, Keys)
    -- [Medium] ASSUMPTION A2: ties on the file date are broken by load time, then file name
    SELECT *
    FROM customers_raw
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(CUSTOMER))
        ORDER BY TRY_TO_DATE(REGEXP_SUBSTR(_SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}')) DESC NULLS LAST,
                 _LOADED_AT::TIMESTAMP_TZ DESC,
                 _SOURCE_FILE DESC
    ) = 1
)
SELECT
    CAST('{{ var("source_name") }}' AS VARCHAR(64)) AS SOURCE_NAME,            -- [High] kickoff source_name
    CAST(UPPER(TRIM(CUSTOMER)) AS VARCHAR(64)) AS CUSTOMER_ID,                -- [High] section 3: trimmed, upper-cased
    CAST(CASE
        WHEN LOWER(TRIM(TYPE)) IN ('privat', 'privatkunde', 'private', 'consumer') THEN 'CONSUMER'
        WHEN LOWER(TRIM(TYPE)) IN ('firma', 'gewerbe', 'business', 'company') THEN 'BUSINESS'
    END AS VARCHAR(16)) AS CUSTOMER_TYPE,                                      -- [High] section 7 CUSTOMER_TYPE; A1: an unknown spelling stays NULL and fails the not-null check
    CAST(NULLIF(TRIM(CITY), '') AS VARCHAR(100)) AS CITY,                      -- [High] section 3: trimmed; NULL when none
    CAST(CASE
        WHEN LOWER(TRIM(COUNTRY)) IN ('de', 'germany', 'deutschland') THEN 'DE'
        WHEN LOWER(TRIM(COUNTRY)) IN ('at', 'austria', 'österreich') THEN 'AT'
        WHEN LOWER(TRIM(COUNTRY)) IN ('ch', 'switzerland', 'schweiz') THEN 'CH'
    END AS VARCHAR(2)) AS COUNTRY_CODE,                                        -- [High] section 7 Countries; NULL when none; A1 for an unknown name
    TRY_TO_DATE(TRIM(REGISTERED), 'DD.MM.YYYY') AS REGISTERED_ON,             -- [High] section 1 Dates: day.month.year
    CASE
        WHEN LOWER(TRIM(NEWSLETTER)) IN ('ja', 'j', 'yes', 'y', 'true', '1') THEN TRUE
        WHEN LOWER(TRIM(NEWSLETTER)) IN ('nein', 'n', 'no', 'false', '0') THEN FALSE
    END AS NEWSLETTER_OPT_IN,                                                  -- [High] section 1 Yes and no
    CAST(REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$') AS VARCHAR(255)) AS SOURCE_FILE, -- [High] file name without its folder
    CONVERT_TIMEZONE('UTC', _LOADED_AT::TIMESTAMP_TZ)::TIMESTAMP_NTZ AS LOADED_AT_UTC -- [High] load time, UTC
FROM latest
