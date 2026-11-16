# Nordwind Outdoor Shop onboarding

Proven in dev: CUSTOMERS, PRODUCTS, ORDERS and ORDER_LINE match the Partner Commerce Data Standard v2.0 and the owner's decisions on the 24 and 25 October 2026 files: 17 of 17 checks passed, none failed.

Source: Nordwind Outdoor GmbH's daily shop exports in `s3://genesis-lab-data-730335510242/data-onboarding/nordwind-outdoor-shop/` (orders, customers and articles, one dated CSV each per day). `merchant.json` is a reference file and is never loaded. `source_name = 'nordwind_outdoor_shop'`.

Target: schema `NORDWIND_OUTDOOR_SHOP` (dev `ANALYTICS_DEV`, production `ANALYTICS`), the four tables the dictionary defines. Raw files land first in `NORDWIND_OUTDOOR_SHOP_BRONZE` (CUSTOMERS_RAW, ARTICLES_RAW, ORDERS_RAW), every column as text plus the file name and load time.

Pipeline: this dbt project, run by a Snowflake task daily at 06:00 Europe/Berlin, two hours after Nordwind's 04:00 export. Each file is loaded once. Every table is merged by its key, and the newest file wins.

## Mapping

Every table carries `SOURCE_NAME = 'nordwind_outdoor_shop'`, `SOURCE_FILE` (the file name the row came from) and `LOADED_AT_UTC` (its load time in UTC). Each key is the newest row by the file's date, then by the latest load.

### CUSTOMERS (key SOURCE_NAME, CUSTOMER_ID), from the customers file
- CUSTOMER_ID: CUSTOMER, trimmed and upper-cased
- CUSTOMER_TYPE: privat/privatkunde/private/consumer -> CONSUMER; firma/gewerbe/business/company -> BUSINESS (any case)
- CITY: CITY trimmed; empty -> NULL
- COUNTRY_CODE: DE/Germany/Deutschland -> DE, AT/Austria/Österreich -> AT, CH/Switzerland/Schweiz -> CH; another two-letter code upper-cased; empty -> NULL
- REGISTERED_ON: REGISTERED read as day.month.year
- NEWSLETTER_OPT_IN: ja/yes/true/1 -> TRUE; nein/no/false/0 -> FALSE

### PRODUCTS (key SOURCE_NAME, SKU), from the articles file
- SKU: ARTICLE, trimmed and upper-cased
- PRODUCT_NAME: NAME trimmed
- CATEGORY: the dictionary's CATEGORY code set, matched trimmed and in any case
- LIST_PRICE: PRICE with decimal comma and thousands dot (`1.249,50` -> 1249.50)
- CURRENCY_CODE: CUR, upper-cased
- IS_ACTIVE: yes/no rule as above

### ORDERS (key SOURCE_NAME, ORDER_ID), from the orders file (one row per order)
- ORDER_ID: ORDER_NO, trimmed and upper-cased
- CUSTOMER_ID: CUSTOMER, upper-cased; empty -> NULL (guest checkout)
- ORDERED_AT_UTC: CREATED read as Europe/Berlin local time, converted to UTC
- ORDER_DATE: CREATED's calendar day in Europe/Berlin
- CURRENCY_CODE: CUR, upper-cased
- SHIP_COUNTRY: SHIP_TO by the country rule above
- The order's details come from its lowest line in the newest file that sent it

### ORDER_LINE (key SOURCE_NAME, ORDER_ID, LINE_NUMBER), from the orders file
- ORDER_ID: ORDER_NO, trimmed and upper-cased; LINE_NUMBER: POS
- SKU: ARTICLE, trimmed and upper-cased
- QUANTITY: QTY
- UNIT_PRICE: PRICE by the amount rule above
- DISCOUNT_PCT: DISCOUNT without `%` (`10`, `10%`, `10 %` -> 10); empty -> 0
- NET_AMOUNT: QUANTITY × UNIT_PRICE × (1 − DISCOUNT_PCT/100), rounded to 2 places
- LINE_STATUS: the dictionary's LINE_STATUS code set, trimmed and in any case (`Shipped `, `canceled`, …)

Relationships: every named order customer is in CUSTOMERS, every line's order is in ORDERS and every order has a line, and every line's SKU is in PRODUCTS.

## Owner's decisions

1. **Nordwind's time zone.** Asked which time zone Nordwind's order times are recorded in, Gabriel Garrett answered on 2026-11-16:
   > Europe/Berlin (German time)
2. **Source name.** Given in the onboarding request: `nordwind_outdoor_shop`.
3. **The mapping.** Gabriel Garrett approved it on 2026-11-16:
   > Approve the mapping

## Assumptions for review

Please check these in review:

- **A1:** an order's details (time, customer, currency, ship-to) come from its lowest line in the newest file that sent it. Today every line of an order agrees.
- **A2:** a country sent as any other two-letter code is kept upper-cased as an ISO code; an empty one is NULL. No current row is affected.
- **A3:** an order line with no customer is a guest checkout (30 of the first day's 412 lines). Nordwind has not confirmed that an empty value always means a guest.
- **A4:** Europe/Berlin applies with daylight saving. A time in the repeated hour when clocks go back is resolved Snowflake's default way.
- **A5:** when two files of one feed carry the same date, the later load wins.

## Proof

[See the proof](https://gabriel.lab.genesiscomputing.io/estate/runs/fd32248838c768964dcb4b7e8b27806c88964fa05399625169545ff2e0b92b80/?replay=open)

Each table's rows and key, every column rule and the three relationships were checked against the raw files in bronze. The full record is `PROVER_VERIFIED.md` in the onboarding Mission's repository.

- Proof on the 24 October files: verified (17 of 17 checks passed)
- Proof on the 24 and 25 October files: verified (17 of 17 checks passed)

## Dev runs (ANALYTICS_DEV, task switched off, run by hand)

| Run | Files | Rows loaded | Tables after |
|---|---|---|---|
| 1 | 24 October: customers, articles, orders | 300 / 46 / 412 | CUSTOMERS 300, PRODUCTS 46, ORDERS 186, ORDER_LINE 412 |
| 2 | 25 October: customers, articles, orders | 14 / 3 / 445 | CUSTOMERS 308, PRODUCTS 47, ORDERS 389, ORDER_LINE 843 |

## Production

Merging deploys it to production through your usual release; until then no table that was there before the Mission was written.

`deploy/snowflake/nordwind_outdoor_shop.sql` creates the production objects in `ANALYTICS.PIPELINES` (file format, stage, Git repository object, dbt project from `main`, and the daily task, resumed). Before release, please confirm that the production role may create these objects and can read the bucket through `GENESIS_ONBOARDING_DEMO_S3` and this repository through `GENESIS_ONBOARDING_DEMO_GIT`.
