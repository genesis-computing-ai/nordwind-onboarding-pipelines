# nordwind_outdoor onboarding pipeline

A dbt project that loads Nordwind Outdoor's daily order files into `NORDWIND_OUTDOOR.ORDER_LINE`, as the Partner Order Data Standard v1.2 defines it. A Snowflake task runs it every day at 06:00 Europe/Berlin, two hours after Nordwind's 04:00 export.

- **Bronze:** `NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW`. Every line of each `nordwind_orders_YYYY-MM-DD.csv` is held as text, with its file and load time. `COPY INTO` loads only files it has not loaded before. `merchant.json` is reference and is never loaded.
- **Target:** `NORDWIND_OUTDOOR.ORDER_LINE`, merged on SOURCE_NAME, ORDER_ID, LINE_NUMBER. The newest file wins for each line.
- **Owner decisions** are set in `dbt_project.yml`: `source_time_zone: Europe/Berlin` and `source_name: nordwind_outdoor`.
- **Dev:** `ANALYTICS_DEV`, task `ANALYTICS_DEV.PIPELINES.NORDWIND_OUTDOOR_DAILY`.
- **Production:** `deploy/snowflake/nordwind_outdoor.sql` deploys the project from `main` into `ANALYTICS`. A production run never does a full refresh.

The mapping, the owner's decisions, the assumptions for review and the proof are added here when the pull request opens.
