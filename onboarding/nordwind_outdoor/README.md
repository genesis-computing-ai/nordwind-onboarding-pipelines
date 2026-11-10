# nordwind_outdoor onboarding pipeline

A dbt project, run every day at 06:00 Europe/Berlin by a Snowflake task. It loads Nordwind Outdoor's daily order files (`nordwind_orders_YYYY-MM-DD.csv`) from the bucket folder `s3://genesis-lab-data-730335510242/data-onboarding/nordwind-outdoor/` into `NORDWIND_OUTDOOR.ORDER_LINE`. The table is built as the Partner Order Data Standard v1.2 defines it.

- **Bronze:** `NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW` holds every file row as text. `COPY INTO` loads only new files.
- **Target:** `NORDWIND_OUTDOOR.ORDER_LINE` is merged on SOURCE_NAME, ORDER_ID and LINE_NUMBER. It keeps the latest file's version of each line.
- **Owner decisions** are project variables: `source_time_zone: Europe/Berlin` and `source_name: nordwind_outdoor`.
- **Production:** `deploy/snowflake/nordwind_outdoor.sql` sets up the same pipeline in `ANALYTICS`, from `main`.

The Hand off phase completes this README with the mapping, the proof and the dev runs.
