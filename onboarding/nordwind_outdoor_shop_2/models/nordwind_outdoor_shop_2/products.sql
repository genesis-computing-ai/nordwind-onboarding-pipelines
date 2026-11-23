-- depends_on: {{ ref('customers') }}
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'sku'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    full_refresh=(false if target.name == 'prod' else none),
    on_schema_change='fail'
) }}

-- Mapping: mapping_PRODUCTS.sql as the owner approved it (mission repo, commit f1a0aab), articles_raw bound to bronze.
WITH articles_raw AS (
    SELECT ARTICLE, NAME, CATEGORY, PRICE, CUR, ACTIVE, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'articles_raw') }}
),
latest AS (
    -- [High] one row per key; the newest file by the date in its name wins (dictionary section 1, Keys)
    -- [Medium] ASSUMPTION A2: ties on the file date are broken by load time, then file name
    SELECT *
    FROM articles_raw
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(ARTICLE))
        ORDER BY TRY_TO_DATE(REGEXP_SUBSTR(_SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}')) DESC NULLS LAST,
                 _LOADED_AT::TIMESTAMP_TZ DESC,
                 _SOURCE_FILE DESC
    ) = 1
)
SELECT
    CAST('{{ var("source_name") }}' AS VARCHAR(64)) AS SOURCE_NAME,            -- [High] kickoff source_name
    CAST(UPPER(TRIM(ARTICLE)) AS VARCHAR(64)) AS SKU,                         -- [High] section 4: trimmed, upper-cased
    CAST(TRIM(NAME) AS VARCHAR(200)) AS PRODUCT_NAME,                         -- [High] section 4: as written, trimmed
    CAST(CASE
        WHEN LOWER(TRIM(CATEGORY)) IN ('zelte', 'tents', 'tarps') THEN 'TENTS'
        WHEN LOWER(TRIM(CATEGORY)) IN ('schlafsäcke', 'isomatten', 'sleeping bags', 'sleeping mats') THEN 'SLEEPING'
        WHEN LOWER(TRIM(CATEGORY)) IN ('beleuchtung', 'lighting') THEN 'LIGHTING'
        WHEN LOWER(TRIM(CATEGORY)) IN ('kochen', 'cooking') THEN 'COOKING'
        WHEN LOWER(TRIM(CATEGORY)) IN ('trinken', 'hydration') THEN 'HYDRATION'
        WHEN LOWER(TRIM(CATEGORY)) IN ('wassersport', 'water sports') THEN 'WATER_SPORTS'
        WHEN LOWER(TRIM(CATEGORY)) IN ('rucksäcke', 'taschen', 'bags') THEN 'BAGS'
        WHEN LOWER(TRIM(CATEGORY)) IN ('bekleidung', 'clothing') THEN 'CLOTHING'
        WHEN LOWER(TRIM(CATEGORY)) IN ('schuhe', 'footwear') THEN 'FOOTWEAR'
        WHEN LOWER(TRIM(CATEGORY)) IN ('ausrüstung', 'equipment') THEN 'EQUIPMENT'
    END AS VARCHAR(16)) AS CATEGORY,                                           -- [High] section 7 CATEGORY; A1: an unknown spelling stays NULL and fails the not-null check
    CAST(TRY_TO_NUMBER(REPLACE(REPLACE(TRIM(PRICE), '.', ''), ',', '.'), 18, 2) AS NUMBER(18,2)) AS LIST_PRICE, -- [High] section 1 Amounts: 1.249,50 reads 1249.50
    CAST(UPPER(TRIM(CUR)) AS VARCHAR(3)) AS CURRENCY_CODE,                    -- [High] section 4: ISO 4217, upper case
    CASE
        WHEN LOWER(TRIM(ACTIVE)) IN ('ja', 'j', 'yes', 'y', 'true', '1') THEN TRUE
        WHEN LOWER(TRIM(ACTIVE)) IN ('nein', 'n', 'no', 'false', '0') THEN FALSE
    END AS IS_ACTIVE,                                                          -- [High] section 1 Yes and no
    CAST(REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$') AS VARCHAR(255)) AS SOURCE_FILE, -- [High] file name without its folder
    CONVERT_TIMEZONE('UTC', _LOADED_AT::TIMESTAMP_TZ)::TIMESTAMP_NTZ AS LOADED_AT_UTC -- [High] load time, UTC
FROM latest
