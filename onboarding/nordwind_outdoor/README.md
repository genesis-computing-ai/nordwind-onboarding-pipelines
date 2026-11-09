# nordwind_outdoor: daily order feed into NORDWIND_OUTDOOR.ORDER_LINE

Proven in dev: "Proof ecrun_64b51b94f9b449d3a2affb00602a9308 against spec 4b80a7763829: grade ecrun_27d3f2d3e23447b0879373544699ccb6 is verified; 9 obligations: 9 passed, 0 failed, 0 errored, 0 unmeasured; couldn't confirm the source or the target didn't change between the two reads (the snowflake source keeps no write history Prover can read; the snowflake target keeps no write history Prover can read); its review opened with 0 items to review, before any was ruled on or withheld; comparison 1cd0a414675d, as the grade classifies it: 17 matched, 0 drift, 0 licensed by the spec, 0 licensed by the platform, 1 derived by the target model, 0 indeterminate, 1 derived table not compared cell by cell (covered by checks), 0 errored read(s)."

Merging deploys it to production through your usual release; until then no table that was there before the Mission was written.

## What it does

- **Source:** Nordwind Outdoor GmbH's daily order export, `nordwind_orders_YYYY-MM-DD.csv`, in `s3://genesis-lab-data-730335510242/data-onboarding/nordwind-outdoor/`. `merchant.json` in the same folder is reference only and is never loaded.
- **Bronze:** `NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW`, every file's rows as sent, plus `_SOURCE_FILE`, `_FILE_ROW_NUMBER` and `_LOADED_AT`. Each run loads only files not loaded before.
- **Target:** `NORDWIND_OUTDOOR.ORDER_LINE`, defined by the Partner Order Data Standard v1.2: one row per order line, holding its latest state. Key: SOURCE_NAME, ORDER_ID, LINE_NUMBER.
- **Schedule:** a Snowflake task runs `dbt build` daily at 06:00 Europe/Berlin, two hours after Nordwind's 04:00 export.
- **Production:** `deploy/snowflake/nordwind_outdoor.sql` deploys this project from `main` into `ANALYTICS`. Set your release's role, warehouse, storage integration and API integration in it first. A production run never does a full refresh.

## Mapping: ORDER_LINE

| # | Column | Rule |
|---|---|---|
| 1 | SOURCE_NAME | the constant `nordwind_outdoor` |
| 2 | ORDER_ID | `UPPER(TRIM(ORDER_NO))` |
| 3 | LINE_NUMBER | `TO_NUMBER(TRIM(POS), 9, 0)` |
| 4 | ORDERED_AT_UTC | CREATED read as Europe/Berlin local time, converted to UTC |
| 5 | ORDER_DATE | the Europe/Berlin calendar date of CREATED |
| 6 | CUSTOMER_REF | `NULLIF(TRIM(CUSTOMER), '')`: blank means a guest checkout |
| 7 | SKU | `UPPER(TRIM(ARTICLE))` |
| 8 | QUANTITY | `TO_NUMBER(TRIM(QTY), 9, 0)` |
| 9 | UNIT_PRICE | drop the thousands `.`, read `,` as the decimal point, NUMBER(18,2) |
| 10 | DISCOUNT_PCT | strip `%` and spaces; blank is 0 |
| 11 | NET_AMOUNT | `ROUND(QUANTITY * UNIT_PRICE * (100 - DISCOUNT_PCT) / 100, 2)` |
| 12 | CURRENCY_CODE | `UPPER(TRIM(CUR))` |
| 13 | LINE_STATUS | the dictionary's status code set (PLACED, SHIPPED, CANCELLED, RETURNED), compared on `LOWER(TRIM(STATUS))` |
| 14 | SHIP_COUNTRY | country names in English or German to ISO (DE, AT, CH); blank is NULL |
| 15 | SOURCE_FILE | the file name without its folder |
| 16 | LOADED_AT_UTC | when the file was loaded, UTC |

Row rule: when an order line arrives in several files, the row from the newest file (by the date in its name, then load time) wins. No line is filtered out.

## Owner's decisions

1. **Nordwind's time zone.** Question: "Nordwind sends order times with no time zone. Which zone are they in?" Answer (gabriel.garrett, 2026-11-09 17:25:42 UTC): "Europe/Berlin". Set as `source_time_zone` in `dbt_project.yml`.
2. **Source name.** Given in the approved kickoff: `source_name = 'nordwind_outdoor'`. Set as `source_name` in `dbt_project.yml`.
3. **Mapping approval.** Question: "The mapping is ready: 1 table in ANALYTICS_DEV.NORDWIND_OUTDOOR, 16 columns, 4 assumptions for your team to review in the pull request. Approve it?" Answer (gabriel.garrett, 2026-11-09 17:31:08 UTC): "Approve the mapping".

## Assumptions for review

Please check each of these:

- **A1, guest customers:** a blank customer is treated as a guest checkout and stored as NULL. The dictionary allows NULL only for guests, and the feed has no other guest marker.
- **A2, latest state across files:** when an order line arrives in several daily files, the file with the latest date in its name wins, with ties broken by load time. This was exercised on 25 October: 14 lines sent again with a new status, each kept once from the newer file.
- **A3, unknown codes:** a status or country name outside the dictionary's lists is not guessed. An unknown status fails the NOT NULL check on LINE_STATUS; an unknown non-blank country fails the `ship_to_country_known` test. Either stops the run so the code can be raised with Nordwind.
- **A4, the clock change:** on the night Berlin puts its clocks back, a local time in the repeated hour is ambiguous, and Snowflake picks one of the two moments. Neither file so far has such a time.

## Proof

- Verdict, word for word: see the first line of this file.
- Spec hash: `4b80a7763829849f3e462bc14558ee4fc3e6c2883e0a704d7068cee031d1c430`
- Prover runs: prove `ecrun_64b51b94f9b449d3a2affb00602a9308`, grade `ecrun_27d3f2d3e23447b0879373544699ccb6`. Earlier rounds: `ecrun_0051d655280d4ef7b44812cd399d7fec` (verified on the first file) and `ecrun_540eef66334b4048bde1abcaaa9d48ff` (one check ruled defective in the check itself, then repaired; no pipeline change).
- What it does not cover: it proves bronze to ORDER_LINE and each file's row count into bronze, not each value on its way into bronze. Snowflake keeps no write history it can read, so it cannot confirm neither table changed between its two reads.

## Dev runs (ANALYTICS_DEV)

| Run | Task run id | Started (UTC) | State | Files (rows) | ORDER_LINE rows after |
|---|---|---|---|---|---|
| 1 | `01c84ce1-030d-0e6a-005b-710733acbfd2` | 2026-11-09 17:37:58 | SUCCEEDED | `nordwind_orders_2026-10-24.csv` (412) | 412 |
| 2 | `01c84cf6-030d-1422-005b-710733ade016` | 2026-11-09 17:58:15 | SUCCEEDED | `nordwind_orders_2026-10-25.csv` (445) | 843 |
