{#- Bronze for the nordwind_orders feed: every file column as text, under the snapshot's names,
    plus _source_file, _file_row_number and _loaded_at. Called as the order_line model's pre_hooks.
    A full refresh (dev only) recreates bronze and reloads every staged file; production never does. -#}

{% macro nordwind_is_dev_full_refresh() -%}
    {{- return(flags.FULL_REFRESH and target.name != 'prod') -}}
{%- endmacro %}

{% macro nordwind_bronze_create_schema() -%}
    create schema if not exists {{ target.database }}.NORDWIND_OUTDOOR_BRONZE
{%- endmacro %}

{% macro nordwind_bronze_create_table() -%}
    {% if flags.FULL_REFRESH and target.name != 'prod' %}create or replace table{% else %}create table if not exists{% endif %}
    {{ target.database }}.NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW (
        order_no varchar, pos varchar, created varchar, customer varchar, article varchar,
        qty varchar, price varchar, discount varchar, cur varchar, status varchar,
        ship_to varchar, exported_at varchar,
        _source_file varchar, _file_row_number number,
        _loaded_at timestamp_ltz default current_timestamp()
    )
{%- endmacro %}

{% macro nordwind_bronze_copy_into() -%}
    {%- set stage = (target.database ~ '.' ~ var('prod_drop_stage')) if target.name == 'prod' else var('drop_stage') -%}
    copy into {{ target.database }}.NORDWIND_OUTDOOR_BRONZE.NORDWIND_ORDERS_RAW
        (order_no, pos, created, customer, article, qty, price, discount, cur, status, ship_to, exported_at,
         _source_file, _file_row_number)
    from (
        select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
               metadata$filename, metadata$file_row_number
        from @{{ stage }}
    )
    pattern = '{{ var('file_pattern') }}'
    file_format = (format_name = '{{ target.database }}.{{ var('file_format') }}')
    force = {{ 'true' if (flags.FULL_REFRESH and target.name != 'prod') else 'false' }}
{%- endmacro %}
