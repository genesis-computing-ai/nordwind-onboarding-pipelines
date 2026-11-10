Proven in dev: Proof ecrun_a3d3ee6268084651b7dce7a8f9c4ddc5 against spec d761ed35bdb1: grade ecrun_aeb8ab3405d447ca86acdf38b5cec3c8 is verified; 5 obligations: 5 passed, 0 failed, 0 errored, 0 unmeasured; couldn't confirm the source or the target didn't change between the two reads (the snowflake source keeps no write history Prover can read; the snowflake target keeps no write history Prover can read); its review opened with 0 items to review, before any was ruled on or withheld; comparison 00fa2a428da9, as the grade classifies it: 17 matched, 0 drift, 0 licensed by the spec, 0 licensed by the platform, 1 derived by the target model, 0 indeterminate, 1 derived table not compared cell by cell (covered by checks), 0 errored read(s); source snapshot af19be6912df37914678530eba2aa5b9675c2b2c63cd01aa24cb0f52e7b67fd2 taken 2026-11-10T00:38:34.339482+00:00 by scan ecrun_fb1cbee974564c9e85cc215fbef848fc; target snapshot ed1e4a39a63bfeb7cb1216702e034b0c5151b504ab65061e47b2d238c0156917 taken 2026-11-10T00:38:37.399479+00:00 by scan ecrun_1c168240f45146e7a66a18d9afc81488.

# nordwind_outdoor onboarding pipeline

Daily order files from Nordwind Outdoor GmbH (Hamburg, DE) land in `s3://genesis-lab-data-730335510242/data-onboarding/nordwind-outdoor/` as `nordwind_orders_YYYY-MM-DD.csv`. This dbt project loads every file into a bronze table, then builds `NORDWIND_OUTDOOR.ORDER_LINE` as the Partner Order Data Standard v1.2 defines it.

- **Bronze:** `NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW`. Every file column is kept as text, plus `_source_file`, `_file_row_number` and `_loaded_at`. Only files not yet loaded are read.
- **Target:** `NORDWIND_OUTDOOR.ORDER_LINE`. It is an incremental merge on SOURCE_NAME, ORDER_ID and LINE_NUMBER, so a line a later file sends again replaces the earlier one.
- **Schedule:** a Snowflake task runs `build` daily at 06:00 Europe/Berlin, two hours after the shop's 04:00 local export.
- **Owner decisions** are project variables: `source_time_zone: Europe/Berlin` and `source_name: nordwind_outdoor`.
- **Production:** `deploy/snowflake/nordwind_outdoor.sql` sets up the same pipeline in `ANALYTICS`, from `main`.

## Mapping: ORDER_LINE

| Column | Rule |
| --- | --- |
| SOURCE_NAME | literal `'nordwind_outdoor'` |
| ORDER_ID | ORDER_NO, trimmed and upper-cased |
| LINE_NUMBER | POS as a number |
| ORDERED_AT_UTC | CREATED parsed as `YYYY-MM-DD HH24:MI:SS` in Europe/Berlin, converted to UTC |
| ORDER_DATE | the Europe/Berlin calendar day of CREATED |
| CUSTOMER_REF | CUSTOMER trimmed; empty means a guest checkout, stored as NULL |
| SKU | ARTICLE, trimmed and upper-cased |
| QUANTITY | QTY as a number |
| UNIT_PRICE | PRICE with the decimal comma read as a point and the thousands dot removed |
| DISCOUNT_PCT | DISCOUNT with `%` and spaces removed; empty means 0 |
| NET_AMOUNT | ROUND(quantity × unit price × (1 − discount / 100), 2) |
| CURRENCY_CODE | CUR, trimmed and upper-cased |
| LINE_STATUS | STATUS mapped to PLACED, SHIPPED, CANCELLED or RETURNED, ignoring case and spaces |
| SHIP_COUNTRY | SHIP_TO names mapped to DE, AT or CH; another two-letter code kept upper-cased; empty means NULL |
| SOURCE_FILE | the file name after the last `/` of the loaded path |
| LOADED_AT_UTC | the load time, in UTC |

The schema holds exactly one object, ORDER_LINE, a BASE TABLE.

## Owner decisions (OWNER_DECISIONS.md)

1. **Time zone.** Asked: "Nordwind's order times arrive with no time zone. Which zone does their shop record them in?" Answer, gabriel.garrett, 2026-11-09 23:57 UTC: "Europe/Berlin (German time)".
2. **SOURCE_NAME.** Set in the approved onboarding kickoff: `source_name = 'nordwind_outdoor'`.
3. **Mapping approval.** Asked: "The mapping is ready: 1 table in ANALYTICS_DEV.NORDWIND_OUTDOOR, 16 columns, 4 assumptions for your team to review in the pull request. Approve it?" Answer, gabriel.garrett, 2026-11-10 00:02 UTC: "Approve the mapping".
4. **The one-table rule.** Asked whether to skip the dictionary's "The schema holds one table." for this run or leave it open until the plan answers it. Answer, gabriel.garrett, 2026-11-10 00:25 UTC: "Leave it open until the plan answers it". The mapping now states that the schema holds exactly ORDER_LINE, and the proof checks it.

## Assumptions for review

- **A1 (latest state):** "later file" is read as the newer date in the file name, with the load time breaking ties.
- **A2 (guest checkout):** an empty CUSTOMER is a guest checkout, stored as NULL (30 of the first 412 lines).
- **A3 (price with no comma):** every price so far uses a decimal comma. A future price with no comma would be read with a dot as its decimal point.
- **A4 (other countries):** a ship-to that is already a two-letter code outside DE, AT and CH is kept as that code. Any other unrecognised name would be stored as NULL.

## Proof

- **Verdict:** see the first line of this file, word for word.
- **Spec hash:** d761ed35bdb147842115db309155d1cc603819289fe757e9bb4047afbf2eec5c
- **Prover runs:**
  - ecrun_9742933c207349f99cc75fa2ae1b9519: round 1, before the one-table rule
  - ecrun_c272b57052004a62b8f20f1a76be836f: round 2, verified on the 24 October file
  - ecrun_a3d3ee6268084651b7dce7a8f9c4ddc5: round 3, verified on both files, grade ecrun_aeb8ab3405d447ca86acdf38b5cec3c8

## Dev runs (ANALYTICS_DEV)

| Run | Task query id | State | File loaded (rows) | ORDER_LINE after |
| --- | --- | --- | --- | --- |
| 1 | 01c84e68-030d-140c-005b-710733b00352 | SUCCEEDED | nordwind_orders_2026-10-24.csv (412) | 412 |
| 2 | 01c84e84-030d-0e0d-005b-710733b35fb6 | SUCCEEDED | nordwind_orders_2026-10-25.csv (445) | 843 |

On 25 October the shop sent 14 of the previous day's lines again; each replaced its earlier version.

Merging deploys it to production through your usual release; until then no table that was there before the Mission was written.
