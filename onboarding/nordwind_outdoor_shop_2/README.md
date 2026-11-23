Proven in dev: CUSTOMERS, PRODUCTS, ORDERS and ORDER_LINE match the Partner Commerce Data Standard (data dictionary v2.0) and the owner's decisions on the files of 24 and 25 October 2026: 19 of 19 checks passed, none failed.

# Nordwind Outdoor Shop 2 onboarding pipeline

Loads Nordwind Outdoor Shop's daily exports from `s3://genesis-lab-data-730335510242/data-onboarding/nordwind-outdoor-shop/` into the four tables the Partner Commerce Data Standard defines, as a dbt project run every day by a Snowflake task.

- **Feeds:** `nordwind_customers_<date>.csv`, `nordwind_articles_<date>.csv`, `nordwind_orders_<date>.csv`. `merchant.json` is a reference file and is not loaded.
- **Bronze:** every file's rows land as text in `NORDWIND_OUTDOOR_SHOP_2_BRONZE` (`CUSTOMERS_RAW`, `ARTICLES_RAW`, `ORDERS_RAW`), with the file name, row number and load time. Each run loads only files it has not loaded yet.
- **Target:** `NORDWIND_OUTDOOR_SHOP_2.CUSTOMERS`, `.PRODUCTS`, `.ORDERS`, `.ORDER_LINE`, merged on each table's key with `SOURCE_NAME = 'nordwind_outdoor_shop_2'`. When a later file sends a key again, the newer file's row is kept.
- **Schedule:** daily at 06:00 Europe/Berlin, two hours after the shop's own 04:00 export. Switched off in dev; `deploy/snowflake/nordwind_outdoor_shop_2.sql` starts it in production.
- **Checks in the project:** enforced contracts for every column, type and NOT NULL in the dictionary (`schema.yml`), one key test per table, and tests for the dictionary's relationships (each order finds its customer, each line its order and its product).

## Mapping

### CUSTOMERS (one row per customer; key SOURCE_NAME, CUSTOMER_ID)

- SOURCE_NAME: the literal `'nordwind_outdoor_shop_2'`
- CUSTOMER_ID: CUSTOMER, trimmed and upper-cased
- CUSTOMER_TYPE: TYPE mapped to the dictionary's CUSTOMER_TYPE codes (Privat → CONSUMER, Firma/Gewerbe → BUSINESS), any case or spacing
- CITY: CITY trimmed; blank → NULL
- COUNTRY_CODE: COUNTRY mapped to DE, AT or CH (Deutschland, Germany, Österreich, Austria, Schweiz, …)
- REGISTERED_ON: REGISTERED read as DD.MM.YYYY
- NEWSLETTER_OPT_IN: NEWSLETTER ja → true, nein → false
- SOURCE_FILE: the file name, without its folder
- LOADED_AT_UTC: the load time, in UTC

### PRODUCTS (one row per article; key SOURCE_NAME, SKU)

- SOURCE_NAME: the literal `'nordwind_outdoor_shop_2'`
- SKU: ARTICLE, trimmed and upper-cased
- PRODUCT_NAME: NAME trimmed
- CATEGORY: CATEGORY mapped to the dictionary's category codes (Zelte → TENTS, Schlafsäcke/Isomatten → SLEEPING, Rucksäcke → BAGS, …)
- LIST_PRICE: PRICE with `.` as thousands separator and `,` as decimal mark (1.249,50 → 1249.50)
- CURRENCY_CODE: CUR trimmed and upper-cased
- IS_ACTIVE: ACTIVE ja → true, nein → false
- SOURCE_FILE: the file name, without its folder
- LOADED_AT_UTC: the load time, in UTC

### ORDERS (one row per order; key SOURCE_NAME, ORDER_ID)

- SOURCE_NAME: the literal `'nordwind_outdoor_shop_2'`
- ORDER_ID: ORDER_NO, trimmed and upper-cased
- CUSTOMER_ID: CUSTOMER, trimmed and upper-cased; blank → NULL (guest checkout)
- ORDERED_AT_UTC: CREATED read as Europe/Berlin time, converted to UTC
- ORDER_DATE: the Berlin calendar day of CREATED
- CURRENCY_CODE: CUR trimmed and upper-cased
- SHIP_COUNTRY: SHIP_TO mapped to DE, AT or CH
- SOURCE_FILE: the newest file that sent a line of the order, without its folder
- LOADED_AT_UTC: the load time, in UTC

### ORDER_LINE (one row per order line; key SOURCE_NAME, ORDER_ID, LINE_NUMBER)

- SOURCE_NAME: the literal `'nordwind_outdoor_shop_2'`
- ORDER_ID: ORDER_NO, trimmed and upper-cased
- LINE_NUMBER: POS as a whole number
- SKU: ARTICLE, trimmed and upper-cased
- QUANTITY: QTY as a whole number
- UNIT_PRICE: PRICE with `.` as thousands separator and `,` as decimal mark
- DISCOUNT_PCT: DISCOUNT with `%` and spaces removed; blank → 0
- NET_AMOUNT: QUANTITY × UNIT_PRICE × (1 − DISCOUNT_PCT / 100), rounded to 2 decimals
- LINE_STATUS: STATUS mapped to PLACED, SHIPPED, CANCELLED or RETURNED, any case or spacing
- SOURCE_FILE: the file name, without its folder
- LOADED_AT_UTC: the load time, in UTC

`EXPORTED_AT` and the file checksum are not carried: the dictionary has no column for them. They stay in bronze.

## Owner's decisions

- **Time zone of order times.** Asked: "Nordwind's order times come with no time zone. Which local zone are they in?" Answer (gabriel.garrett, 2026-11-23 05:00:52 UTC): "Europe/Berlin (German time)". Applied to ORDERS.ORDERED_AT_UTC and ORDERS.ORDER_DATE.
- **Source name.** Given at kickoff: `source_name = 'nordwind_outdoor_shop_2'`.
- **The mapping.** Asked: "The mapping is ready: 4 tables in ANALYTICS_DEV.NORDWIND_OUTDOOR_SHOP_2, 38 columns, 4 assumptions for your team to review in the pull request. Approve it?" Answer (gabriel.garrett, 2026-11-23 05:12:50 UTC): "Approve the mapping".

## Assumptions for review

Please check these in review:

- **A1: an unknown code is not guessed.** A spelling in none of a code set's rows (status, customer type, category, country) is stored NULL. On a NOT NULL column that fails the table's checks, and the partner's owner is asked (dictionary §7). None in today's files.
- **A2: two files with the same date.** When one key arrives in two files of the same date, the later-loaded one wins, then the later file name. The dictionary says only "the later file". One file per feed per day so far.
- **A3: an order's details.** ORDERS takes customer, time, currency and ship-to from the newest file that sent a line of the order and, within it, the lowest line position. None of the orders so far disagree between their lines.
- **A4: the repeated autumn hour.** A local time in the hour German clocks repeat when they go back (02:00–03:00 on the last Sunday of October) cannot say which of the two it was; it is converted by Snowflake's rule for that hour. No order so far falls in that hour.

## Proof

[See the proof](https://demo.lab.genesiscomputing.io/estate/runs/bd95850f8df7ddea4bebeb1ff27b344f12f04f1a2e49ff438e456792515794e3/?replay=open)

The full record is `PROVER_VERIFIED.md` in the Mission's repository.

- Proof on the 24 October files: verified, 19 of 19 checks passed.
- Proof on the 24 and 25 October files: verified, 19 of 19 checks passed.

The checks cover each table's rows and key against the rows the mapping keeps from the bronze tables, every column's rule, the dictionary's relationships between the tables, and that the schema holds exactly the four tables. What they do not cover: each file value on its way into bronze (only that every row of every file arrived), and anything that runs in production.

## Dev runs

| Run (UTC) | Files loaded (rows) | Bronze rows after | Target rows after |
|---|---|---|---|
| 2026-11-23 05:20 | customers 24 Oct (300), articles 24 Oct (46), orders 24 Oct (412) | CUSTOMERS_RAW 300, ARTICLES_RAW 46, ORDERS_RAW 412 | CUSTOMERS 300, PRODUCTS 46, ORDERS 186, ORDER_LINE 412 |
| 2026-11-23 05:45 | customers 25 Oct (14), articles 25 Oct (3), orders 25 Oct (445) | CUSTOMERS_RAW 314, ARTICLES_RAW 49, ORDERS_RAW 857 | CUSTOMERS 308, PRODUCTS 47, ORDERS 389, ORDER_LINE 843 |

Both runs succeeded, neither as a full refresh, and every row of every file reached bronze.

Merging deploys it to production through your usual release; until then no table that was there before the Mission was written.

For the team to confirm before releasing: the production role (`GENESIS_SVC_ROLE`) and warehouse (`XSMALL`) in `profiles.yml`, and that the role may create the objects in `deploy/snowflake/nordwind_outdoor_shop_2.sql` and read the bucket folder and this repository through the storage and Git integrations it names.
