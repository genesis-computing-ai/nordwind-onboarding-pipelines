# nordwind_outdoor — daily order files into NORDWIND_OUTDOOR

Proven in dev: verified — all 14 checks passed on the 843 order lines ORDER_LINE holds after loading the files of 24 and 25 October 2026, with nothing failed, errored or unmeasured; the one-table rule (dictionary 1.2) is accepted by the business owner until 2026-12-05.

## What it does

A dbt project run every day at 06:00 Europe/Berlin by a Snowflake task. It loads each new
`nordwind_orders_<YYYY-MM-DD>.csv` from the Nordwind bucket folder into a bronze table (every column as text,
plus file name, row number and load time), then merges it into `NORDWIND_OUTDOOR.ORDER_LINE` as the Partner
Order Data Standard v1.2 defines it. `merchant.json` in the same folder is reference only and is never loaded.

| Layer | Table |
|---|---|
| Bronze | `NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW` |
| Target | `NORDWIND_OUTDOOR.ORDER_LINE` (one row per SOURCE_NAME, ORDER_ID, LINE_NUMBER; latest file wins) |

## Mapping — ORDER_LINE

| Column | Rule |
|---|---|
| SOURCE_NAME | literal `'nordwind_outdoor'` |
| ORDER_ID | `UPPER(TRIM(ORDER_NO))` |
| LINE_NUMBER | `TRIM(POS)` as NUMBER(9,0) |
| ORDERED_AT_UTC | CREATED parsed `YYYY-MM-DD HH24:MI:SS`, converted from Europe/Berlin to UTC |
| ORDER_DATE | the Berlin calendar day of CREATED |
| CUSTOMER_REF | `NULLIF(TRIM(CUSTOMER), '')` (empty = guest checkout, A2) |
| SKU | `UPPER(TRIM(ARTICLE))` |
| QUANTITY | `TRIM(QTY)` as NUMBER(9,0) |
| UNIT_PRICE | PRICE with the thousands `.` dropped and the decimal `,` turned into `.`, NUMBER(18,2) |
| DISCOUNT_PCT | DISCOUNT with `%` and spaces stripped, empty = 0, NUMBER(5,2) |
| NET_AMOUNT | `ROUND(QUANTITY * UNIT_PRICE * (1 - DISCOUNT_PCT / 100), 2)` |
| CURRENCY_CODE | `UPPER(TRIM(CUR))` |
| LINE_STATUS | trimmed, upper-cased, mapped by dictionary section 4 to PLACED, SHIPPED, CANCELLED, RETURNED |
| SHIP_COUNTRY | country names mapped to ISO (DE, AT, CH) by dictionary section 4; other two-letter values as given (A3) |
| SOURCE_FILE | the file name after the last `/` |
| LOADED_AT_UTC | the bronze load time, in UTC |

Not carried: EXPORTED_AT (one value per file; the dictionary defines no column for it) and `_source_sha256`.

## The business owner's decisions

Recorded with gabriel.garrett's exact words:

1. Order time zone — "German time (Europe/Berlin)" (2026-11-05 21:32 UTC).
2. Source name — "source_name = 'nordwind_outdoor'" (kickoff, 2026-11-05).
3. Mapping — "Approve the mapping" (2026-11-05 21:37 UTC).
4. One-table rule (dictionary 1.2) — "Accept it as checked by the whole-schema scan", "For 30 days (until 2026-12-05)" (2026-11-05 22:29 and 22:31 UTC).
5. Second file before handoff — "Wait for tomorrow's file and prove it too" (2026-11-05 22:41 UTC).

## Assumptions for review

Please check these; each is the team's to confirm or change.

| Id | Assumption |
|---|---|
| A2 | An empty CUSTOMER is a guest checkout and is stored as NULL (30 of the first file's 412 lines). |
| A3 | A two-letter SHIP_TO not in the dictionary's list is taken as an ISO code as sent (no line so far). |
| A4 | When one order line arrives in several files, the file with the latest date in its name wins, then the latest load (14 lines so far, each taken from the 25 October file). |

## Proof

Proof of record, word for word:

> Proof ecrun_71d8bfd3f930420e82e0ce7f22041802 against spec 7788391136b7: grade ecrun_550a351cb7074049a6b6bab655cfba10 is Partially specified · 1 clause open; clauses the seal left open, which nothing proved: order_data_dictionary (Partner Order Data Standard v1.2)#1.2 (each with its remedy in open_clauses); 14 obligations: 14 passed, 0 failed, 0 errored, 0 unmeasured; couldn't confirm the source or the target didn't change between the two reads (the snowflake source keeps no write history Prover can read; the snowflake target keeps no write history Prover can read); 1 mapping clause was not checked by any sealed check (the seal accounted it not applicable): MAPPING_SPECIFICATION.md#T4.2 (The bronze relation holds no _source_sha256 column, so there is nothing to leave unread); its review opened with 1 item to review, before any was ruled on or withheld; comparison 346d9911fa6f, as the grade classifies it: 17 matched, 0 drift, 0 licensed by the spec, 0 licensed by the platform, 1 derived by the target model, 0 indeterminate, 1 derived table not compared cell by cell (covered by checks), 0 errored read(s); source snapshot 502196ed0a0ea21e983003f57b9ef8c83bc760664ecad801f352f64f9a079399 taken 2026-11-05T22:47:33.757153+00:00 by scan ecrun_60f77f880af4440286e44fed959570fa; target snapshot 3f7b05f0aca96b4b5137b58ee87797102454bb277999cd42d28050841c53f6bd taken 2026-11-05T22:47:37.237815+00:00 by scan ecrun_9ebcdb6ce05145bfb586fe429c926cc4

That open clause is the one-table rule, which the business owner accepted until 2026-12-05; with it accepted
the review reads verified, with nothing left to decide.

| | |
|---|---|
| Spec | `7788391136b733e0b1201efb708c8b7e7fb03537b4ec0677559953115b4bdf88` |
| Proof run | `ecrun_71d8bfd3f930420e82e0ce7f22041802` |
| Grade run | `ecrun_550a351cb7074049a6b6bab655cfba10` |
| Comparison | `346d9911fa6f87ff473120db9c777946afe70c99df1cc56ed507ed307fce9b5d` |

## Dev runs (ANALYTICS_DEV)

| Run | Task run | Finished (UTC) | File | Rows in file | Rows loaded | ORDER_LINE rows after |
|---|---|---|---|---|---|---|
| 1 | `01c83757-020c-e057-005b-71073376755a` | 2026-11-05 21:43:58 | nordwind_orders_2026-10-24.csv | 412 | 412 | 412 |
| 2 | `01c83795-020c-e057-005b-71073377541e` | 2026-11-05 22:46:36 | nordwind_orders_2026-10-25.csv | 445 | 445 | 843 |

## Production

Merging deploys it to production through your usual release; until then no table that was there before the Mission was written.
The production definition is `deploy/snowflake/nordwind_outdoor.sql` (dbt project and daily task in
`ANALYTICS.PIPELINES`, target `ANALYTICS.NORDWIND_OUTDOOR`, `build --target prod`).
