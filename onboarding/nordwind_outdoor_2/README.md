# Nordwind Outdoor 2 → NORDWIND_OUTDOOR_2.ORDER_LINE

Proven in dev: ORDER_LINE matches the Partner Order Data Standard v1.2 and the owner's decisions on the 24 and 25 October 2026 order files: 7 of 7 checks passed, none failed.

## What this pipeline does

A dbt project, run every day at 06:00 Europe/Berlin by a Snowflake task (two hours after the shop's 04:00 export).

1. **Bronze** — `NORDWIND_OUTDOOR_2_BRONZE.NORDWIND_ORDERS_RAW`: every `nordwind_orders_YYYY-MM-DD.csv` file in the bucket folder, every column as text, with the file it came from and when it was loaded. Only files not loaded before are read. `merchant.json` describes the shop and is never loaded.
2. **ORDER_LINE** — `NORDWIND_OUTDOOR_2.ORDER_LINE`: one row per order line, holding the latest state of the line. When a later file sends a line again, the later file's values replace the earlier ones.

## Mapping (ORDER_LINE)

| Column | Rule |
|---|---|
| SOURCE_NAME | `nordwind_outdoor_2` on every row |
| ORDER_ID | order number, trimmed and upper-cased |
| LINE_NUMBER | line position |
| ORDERED_AT_UTC | order time, read as Europe/Berlin local time and converted to UTC |
| ORDER_DATE | the Europe/Berlin calendar day of the order |
| CUSTOMER_REF | customer id, trimmed; empty means a guest checkout (NULL) |
| SKU | article code, trimmed and upper-cased |
| QUANTITY | units ordered |
| UNIT_PRICE | price read with a decimal comma (1.249,50 → 1249.50) |
| DISCOUNT_PCT | discount with spaces and % removed (10, 10%, 10 % all mean 10); none given → 0 |
| NET_AMOUNT | QUANTITY × UNIT_PRICE × (1 − DISCOUNT_PCT / 100), rounded half up to 2 decimals |
| CURRENCY_CODE | currency, trimmed and upper-cased |
| LINE_STATUS | status spelling mapped to PLACED, SHIPPED, CANCELLED or RETURNED (dictionary section 4) |
| SHIP_COUNTRY | ship-to mapped to its ISO code (Deutschland/Germany → DE, Österreich/Austria → AT, Schweiz/Switzerland → CH) |
| SOURCE_FILE | the file the row's current values came from, without its folder |
| LOADED_AT_UTC | when the pipeline loaded that file, UTC |

Not carried: `EXPORTED_AT` (export metadata the definition has no column for).

## The owner's decisions

- **Time zone of the order times** — asked: "Nordwind's order times arrive with no time zone. Which time zone are they in?" Answer (gabriel.garrett, 2026-11-10 14:15 UTC): "Europe/Berlin (German time)". It is the project variable `source_time_zone`.
- **Source name** — `nordwind_outdoor_2`, from the approved kickoff (project variable `source_name`).
- **The mapping** — asked: "The mapping is ready: 1 table in ANALYTICS_DEV.NORDWIND_OUTDOOR_2, 16 columns, 6 assumptions for your team to review in the pull request. Approve it?" Answer (gabriel.garrett, 2026-11-10 14:24:54 UTC): "Approve the mapping".

## Assumptions for review

Please check these before merging.

1. A status spelling the dictionary does not list is left empty, so the table's not-null rule stops the run and the spelling is raised with the shop's owner instead of guessed. (None in the files so far.)
2. A price sent with no decimal comma is read with a dot as its decimal point. (Every price so far has a comma.)
3. A ship-to value that is not a listed country name but is two letters is stored as an upper-case ISO code; anything else is left empty.
4. "A later file" means the file with the later date in its name; a tie falls to the later load, then the file name.
5. LOADED_AT_UTC is when the pipeline loaded the file into its raw table.
6. On the night German summer time ends, the repeated 02:00–02:59 hour is read as summer time.
7. **Production settings:** the production deploy (`deploy/snowflake/nordwind_outdoor_2.sql`) targets the database `ANALYTICS`. It creates the schema `ANALYTICS.PIPELINES` if it is missing, a file format, the stage `ANALYTICS.PIPELINES.NORDWIND_OUTDOOR_2_DROP` over the same bucket folder through the storage integration `GENESIS_ONBOARDING_DEMO_S3`, the Git repository object through `GENESIS_ONBOARDING_DEMO_GIT`, the dbt project `NORDWIND_OUTDOOR_2_PIPELINE_PROD` from `main`, and the daily task `NORDWIND_OUTDOOR_2_DAILY_PROD`. The prod profile runs as `GENESIS_SVC_ROLE` on warehouse `XSMALL`: confirm that role may create these objects and read the folder and the repository, or set your release's role.

## Proof

[See the proof](https://gabriel.lab.genesiscomputing.io/estate/runs/55660992bb014ef918aae622b3c5ca4696b81f613d1c86f65690d97876179afc/?replay=open)

The full record is `PROVER_VERIFIED.md` in the Mission's repository.

- Proof on the 24 October file: verified, 7 of 7 checks passed.
- Proof on the 24 and 25 October files: verified, 7 of 7 checks passed.

What it covers: the raw orders table to ORDER_LINE, against the dictionary, the approved mapping and the owner's decisions, and each file's row count from the bucket to the raw table. It does not check each file value on its way into the raw table. Snowflake keeps no record of what wrote a table, so the pipeline's own run and load history below is the record that the pipeline produced ORDER_LINE.

## Runs in dev (ANALYTICS_DEV)

| Run | When (UTC) | File loaded | Lines | Raw rows after | ORDER_LINE rows after |
|---|---|---|---|---|---|
| 1 | 2026-11-10 14:30–14:31 | nordwind_orders_2026-10-24.csv | 412 | 412 | 412 |
| 2 | 2026-11-10 14:50 | nordwind_orders_2026-10-25.csv | 445 | 857 | 843 |

Run 2 loaded only the new file. 14 lines from 24 October were sent again on 25 October; ORDER_LINE keeps the newer values.

Merging deploys it to production through your usual release; until then no table that was there before the Mission was written.
