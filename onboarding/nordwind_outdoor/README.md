# nordwind_outdoor → STANDARD.ORDER_LINE

Onboards Nordwind Outdoor's daily order export (`nordwind_orders_<YYYY-MM-DD>.csv` in `s3://genesis-lab-data-730335510242/data-onboarding/nordwind-outdoor/`) into the standard order-line table, as a dbt project run inside Snowflake by a daily task at 06:00 Europe/Berlin, two hours after the source's 04:00 local export.

Merging deploys it to production through your usual release; nothing in production changed before this.

## How it works
- **Bronze:** a pre-hook `COPY INTO` loads only new files into `<db>.NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW`. Every file column lands as text, plus `_source_file`, `_file_row_number` and `_loaded_at`. `merchant.json` is reference only and is never loaded.
- **Standard:** `models/standard/order_line.sql` is an incremental merge on (source_name, order_id, line_number), scoped to `source_name = 'nordwind_outdoor'`. It keeps the newest file's row per line. Full refresh is disabled on the prod target, so the shared table is never replaced.
- **Contract:** `models/schema.yml` enforces the standard's 16 column types and NOT NULLs, and carries its column descriptions. The tests cover grain uniqueness, QUANTITY ≥ 1 and the LINE_STATUS values.
- **Production deploy definition:** `deploy/snowflake/nordwind_outdoor.sql`.

## Mapping (approved by the owner, 2026-11-03 17:04:57 UTC)

| Standard column | Rule |
|---|---|
| SOURCE_NAME | literal `'nordwind_outdoor'` |
| ORDER_ID | `UPPER(TRIM(ORDER_NO))` |
| LINE_NUMBER | `POS` as a number |
| ORDERED_AT_UTC | `CREATED`, read as Europe/Berlin local time, converted to UTC (DST-aware) |
| ORDER_DATE | the Berlin calendar day of `CREATED` |
| CUSTOMER_REF | trimmed `CUSTOMER`; empty → NULL (guest checkout) |
| SKU | `UPPER(TRIM(ARTICLE))` |
| QUANTITY | `QTY` as a number |
| UNIT_PRICE | `PRICE` in German number format (`1.049,00` → 1049.00) |
| DISCOUNT_PCT | `DISCOUNT` with `%` and spaces removed; empty → 0 |
| NET_AMOUNT | `ROUND(QUANTITY × UNIT_PRICE × (1 − DISCOUNT_PCT/100), 2)` |
| CURRENCY_CODE | `UPPER(TRIM(CUR))` |
| LINE_STATUS | trim + upper; `CANCELED` → `CANCELLED` |
| SHIP_COUNTRY | DE/Germany/Deutschland → DE, AT/Austria/Österreich → AT, CH/Switzerland/Schweiz → CH, otherwise NULL |
| SOURCE_FILE | the file name without its folder |
| LOADED_AT_UTC | the time the file was loaded, in UTC |

Row rule: one row per order line. When a line appears in several daily files, the newest file (by the date in its name) wins, then the latest `EXPORTED_AT`.

## Owner's decisions
1. *"Nordwind Outdoor sends its order times without a time zone. Which local time are they in?"* Answer from gabriel.garrett, 2026-11-03 17:00:26 UTC: **"German time (Europe/Berlin)"**. This is the project variable `source_time_zone`.
2. *"The mapping is ready: 16 standard columns, 6 assumptions for your team to review in the pull request. Approve it?"* Answer from gabriel.garrett, 2026-11-03 17:04:57 UTC: **"Approve the mapping"**.

## Assumptions for review
- **A1:** when a line comes back in a later daily file, the newest file wins (merchant.json: the export carries orders "created or changed the previous day").
- **A2:** an empty customer is a guest checkout and becomes NULL (30 lines in the first file).
- **A3:** prices use German number format: the dot separates thousands and the comma marks decimals.
- **A4:** a discount written without `%` is still a percent (`10`, `10%` and `10 %` all mean 10); an empty discount means 0.
- **A5:** `canceled` is the same status as `cancelled`.
- **A6:** a delivery-country name the mapping doesn't know loads as NULL.
- **A7, production deploy:** `profiles.yml` prod and `deploy/snowflake/nordwind_outdoor.sql` reuse the dev role `GENESIS_SVC_ROLE`, the warehouse `XSMALL` and the dev drop stage `ANALYTICS_DEV.PIPELINES.NORDWIND_OUTDOOR_DROP`. They also assume a Git repository object `ANALYTICS.PIPELINES.NORDWIND_ONBOARDING_PIPELINES`. Set your release's role, stage and repository object before running.

## Proof (Genesis Prover, dev)
Verified: all 16 checks passed. The spec is `1b968817a52c0880b40c8bc81a0977394061fe964422e3fb1e93029782addfda`; the proof run is `ecrun_d87a5810816e44469ded685c0b30f333` and its grade run `ecrun_d288e4c239744d99869087d918483dea`. The earlier verified proof on the first file alone is `ecrun_479af6093bcf44749fb2a8351441a74e`.

> Proof ecrun_d87a5810816e44469ded685c0b30f333 against spec 1b968817a52c: grade ecrun_d288e4c239744d99869087d918483dea is verified; 16 obligations: 16 passed, 0 failed, 0 errored, 0 unmeasured; couldn't confirm the source or the target didn't change between the two reads (the snowflake source keeps no write history Prover can read; the snowflake target keeps no write history Prover can read); its review opened with 0 items to review, before any was ruled on or withheld; comparison c03fd9c369b1, as the grade classifies it: 17 matched, 0 drift, 0 licensed by the spec, 0 licensed by the platform, 1 derived by the target model, 0 indeterminate, 1 derived table not compared cell by cell (covered by checks), 0 errored read(s); source snapshot 6c50dd79f4eb801a7465019479a8cf2d168e8816742cbf93c852bb140b53a715 taken 2026-11-03T17:24:25.700949+00:00 by scan ecrun_aef5a7cdc86d4ad9b55638bfc2d2713d; target snapshot 021f49e5074eab013777765fd97103c15b1ac8fa99212743b4f6467d1ccdee81 taken 2026-11-03T17:24:27.885115+00:00 by scan ecrun_35c5520ca9be41a8a8f696a142f5590c; the spec relies on no recorded clarification; any clarification written into the plan's text has no record behind it and counts as unratified.

The proof checks bronze against the standard table, and each file's row count from the staged file to bronze. It does not check each file value on its way into bronze.

## Dev runs (ANALYTICS_DEV)

| Run (task query id) | File | Rows | Standard rows after |
|---|---|---|---|
| 01c82b06-020c-c3ac-005b-7107335d0126 | nordwind_orders_2026-10-24.csv | 412 | 412 |
| 01c82b12-020c-ca3a-005b-7107335c71b2 | nordwind_orders_2026-10-25.csv | 445 | 843 (14 lines appear in both files; the newer file wins) |
