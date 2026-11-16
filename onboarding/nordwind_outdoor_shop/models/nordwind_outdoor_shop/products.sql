-- depends_on: {{ ref('customers') }}
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['source_name', 'sku'],
    incremental_predicates=["DBT_INTERNAL_DEST.source_name = '" ~ var('source_name') ~ "'"],
    on_schema_change='fail',
    full_refresh=(false if target.name == 'prod' else none)
) }}
-- Approved mapping: mapping_PRODUCTS.sql (mission repo, commit 01bcefd), articles_raw bound to bronze.
WITH articles_raw AS (
    SELECT ARTICLE, NAME, CATEGORY, PRICE, CUR, ACTIVE, EXPORTED_AT, _SOURCE_FILE, _LOADED_AT
    FROM {{ source('bronze', 'articles_raw') }}
),
ranked AS (
    SELECT r.*,
           REGEXP_SUBSTR(r._SOURCE_FILE, '[0-9]{4}-[0-9]{2}-[0-9]{2}') AS FILE_DATE,
           r._LOADED_AT::timestamp_tz AS LOADED_TZ
    FROM articles_raw r
),
latest AS (
    SELECT * FROM ranked
    QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(ARTICLE))
                               ORDER BY FILE_DATE DESC, LOADED_TZ DESC, _SOURCE_FILE DESC) = 1
)
SELECT
    CAST('nordwind_outdoor_shop' AS VARCHAR(64))                       AS SOURCE_NAME,
    CAST(UPPER(TRIM(ARTICLE)) AS VARCHAR(64))                          AS SKU,
    CAST(TRIM(NAME) AS VARCHAR(200))                                   AS PRODUCT_NAME,
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
    END AS VARCHAR(16))                                                AS CATEGORY,
    CAST(REPLACE(REPLACE(TRIM(PRICE), '.', ''), ',', '.') AS NUMBER(18, 2)) AS LIST_PRICE,
    CAST(UPPER(TRIM(CUR)) AS VARCHAR(3))                               AS CURRENCY_CODE,
    CASE
        WHEN LOWER(TRIM(ACTIVE)) IN ('ja', 'j', 'yes', 'y', 'true', '1') THEN TRUE
        WHEN LOWER(TRIM(ACTIVE)) IN ('nein', 'n', 'no', 'false', '0') THEN FALSE
    END                                                                AS IS_ACTIVE,
    CAST(REGEXP_SUBSTR(_SOURCE_FILE, '[^/]+$') AS VARCHAR(255))        AS SOURCE_FILE,
    CONVERT_TIMEZONE('UTC', LOADED_TZ)::timestamp_ntz                  AS LOADED_AT_UTC
FROM latest
