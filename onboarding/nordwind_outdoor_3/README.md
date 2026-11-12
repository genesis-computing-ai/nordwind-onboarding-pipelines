# Nordwind Outdoor 3 onboarding pipeline

Proven in dev: ORDERS and ORDER_LINES match the approved mapping and the owner's decisions on the 24 October 2026 file: 8 of 8 checks passed, none failed.

## What it does

A dbt project, run every day at 06:00 Europe/Berlin by a Snowflake task (two hours after Nordwind's 04:00 local export). Each run:

1. Loads every new `nordwind_orders_YYYY-MM-DD.csv` from the bucket folder `s3://genesis-lab-data-730335510242/data-onboarding/nordwind-outdoor/` into `NORDWIND_OUTDOOR_3_BRONZE.NORDWIND_ORDERS_RAW` (every column as text, plus the file name, row number and load time). `merchant.json` is reference only and never loaded.
2. Merges orders into `NORDWIND_OUTDOOR_3.ORDERS` and order lines into `NORDWIND_OUTDOOR_3.ORDER_LINES`, keeping the newest file's version of each order and line.

## Mapping

### ORDERS (one row per order, key ORDER_NO)

| Column | Rule |
|---|---|
| ORDER_NO | ORDER_NO, trimmed |
| ORDER_CREATED_AT_UTC | CREATED, read as German local time (Europe/Berlin), converted to UTC |
| CUSTOMER_ID | CUSTOMER, trimmed; blank becomes NULL |
| SHIP_TO_COUNTRY_CODE | SHIP_TO: DE/Deutschland/Germany -> DE, AT/Österreich/Austria -> AT, CH/Schweiz/Switzerland -> CH; anything else NULL |
| CURRENCY_CODE | CUR, upper-cased (EUR) |
| EXPORTED_AT_UTC | EXPORTED_AT (carries its zone), in UTC |
| SOURCE_NAME | constant 'nordwind_outdoor_3' |
| SOURCE_FILE | file name the row came from |
| LOADED_AT | when that file was loaded |

### ORDER_LINES (one row per order line, key ORDER_NO, LINE_NO)

| Column | Rule |
|---|---|
| ORDER_NO | ORDER_NO, trimmed |
| LINE_NO | POS as a number |
| ARTICLE_CODE | ARTICLE, trimmed and upper-cased |
| QUANTITY | QTY as a number |
| UNIT_PRICE | PRICE in German number format (1.049,00 -> 1049.00) |
| DISCOUNT_PCT | DISCOUNT with % and spaces removed; blank means 0 |
| LINE_STATUS | STATUS, trimmed and lower-cased, 'canceled' -> 'cancelled' (placed, shipped, cancelled, returned) |
| SOURCE_NAME | constant 'nordwind_outdoor_3' |
| SOURCE_FILE | file name the row came from |
| LOADED_AT | when that file was loaded |

## The owner's decisions

1. Time zone of order times: "Nordwind's order times arrive without a time zone. Which zone are they in? — German time (Europe/Berlin)" (john.dacosta, 2026-11-12 19:05 UTC). Set as the project variable `source_time_zone`.
2. Mapping approval: "Approve the mapping" (john.dacosta, 2026-11-12 19:10 UTC).
3. After the first proof: "Hand off now" (john.dacosta, 2026-11-12 20:06 UTC).

## Assumptions for review

- **A1 Grain:** one row per order in ORDERS and one per order line in ORDER_LINES (order number plus position is unique on all 412 lines; order header fields are the same on every line of an order).
- **A2 Blank discount is no discount:** 289 of 412 lines have an empty discount, read as 0 %; every filled-in value is 5 to 20.
- **A3 Blank customer is kept:** 11 orders (30 lines) carry no customer number and are kept with CUSTOMER_ID NULL, likely guest checkouts.
- **A4 Newest file wins:** each export carries orders created or changed the previous day, so a resent order or line replaces its older version.
- **A5 Unknown country spelling:** a ship-to spelling not seen yet is loaded as NULL rather than guessed.
- **Production database `ANALYTICS`:** the deploy file creates, if missing, the schema `ANALYTICS.PIPELINES`, the file format `NORDWIND_OUTDOOR_3_CSV`, the stage `NORDWIND_OUTDOOR_3_DROP` over the same bucket folder (storage integration `GENESIS_ONBOARDING_DEMO_S3`) and the Git repository object `NORDWIND_ONBOARDING_PIPELINES` (API integration `GENESIS_ONBOARDING_DEMO_GIT`). Confirm the production role may create them and read the folder and repository through them.
- **Production role and warehouse:** the `prod` profile and task run as `GENESIS_SVC_ROLE` on `XSMALL`; set your release role if it differs.

## Proof

[See the proof](https://gabriel.lab.genesiscomputing.io/estate/runs/4a6593acd5507e741b3e48d445dd3de06d7ca0fdf2492cbdc6af00d8631388ad/?replay=open)

The full record is PROVER_VERIFIED.md in the onboarding Mission's repository.

- Proof on the 24 October 2026 file: verified, 8 of 8 checks passed (one row per key, every order and line arrived and nothing else, values as mapped, every line belongs to an order, the schema holds exactly ORDERS and ORDER_LINES).

What it does not cover: it proves the raw table to ORDERS and ORDER_LINES and each file's row count, not each file value on its way into the raw table. Snowflake keeps no write history the check can read, so it cannot say which process wrote the tables; the run record below shows the pipeline built them.

## Dev runs

| Run | When (UTC) | Result | File loaded | Raw rows | ORDERS | ORDER_LINES |
|---|---|---|---|---|---|---|
| First run | 2026-11-12 19:16 | succeeded | nordwind_orders_2026-10-24.csv (412 lines) | 412 | 186 | 412 |

## Deploying

Merging deploys it to production through your usual release (`deploy/snowflake/nordwind_outdoor_3.sql`); until then no table that was there before the Mission was written.
