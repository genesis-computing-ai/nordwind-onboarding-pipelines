{% macro rehearsal_namespace() %}
    {% set run_id = env_var('DBT_RUN_ID') | upper %}
    {% set database = env_var('DBT_DATABASE') | upper %}
    {% if not modules.re.fullmatch('[A-Z0-9]{8,24}', run_id) %}
        {{ exceptions.raise_compiler_error('DBT_RUN_ID must contain 8-24 letters or digits.') }}
    {% endif %}
    {% if not modules.re.fullmatch('[A-Z][A-Z0-9_]{0,200}_DEV', database) %}
        {{ exceptions.raise_compiler_error('The rehearsal requires an explicit development database ending in _DEV.') }}
    {% endif %}
    {% set raw_schema = 'NORDWIND_REHEARSAL_' ~ run_id ~ '_RAW' %}
    {% set output_schema = 'NORDWIND_REHEARSAL_' ~ run_id ~ '_OUT' %}
    {% if target.name != 'rehearsal' or (target.database | upper) != database or (target.schema | upper) != output_schema %}
        {{ exceptions.raise_compiler_error('The selected profile must match this isolated rehearsal namespace.') }}
    {% endif %}
    {% if flags.FULL_REFRESH %}
        {{ exceptions.raise_compiler_error('Full refresh is disabled; use a new empty rehearsal namespace.') }}
    {% endif %}
    {% if not modules.re.fullmatch('[a-z][a-z0-9_]{0,49}', var('source_name') | string) %}
        {{ exceptions.raise_compiler_error('source_name must be a simple lowercase identifier.') }}
    {% endif %}
    {% if var('source_time_zone') != 'Europe/Berlin' %}
        {{ exceptions.raise_compiler_error('This synthetic fixture uses Europe/Berlin timestamps.') }}
    {% endif %}
    {% if not modules.re.fullmatch('nordwind_orders_[0-9]{4}-[0-9]{2}-[0-9]{2}[.]csv', var('fixture_file') | string) %}
        {{ exceptions.raise_compiler_error('fixture_file must name one Nordwind daily CSV, without a path.') }}
    {% endif %}
    {{ return({'database': database, 'raw_schema': raw_schema, 'output_schema': output_schema}) }}
{% endmacro %}

{% macro rehearsal_raw_schema() -%}
    {% set ns = rehearsal_namespace() %}
    {{ return(adapter.quote(ns.database) ~ '.' ~ adapter.quote(ns.raw_schema)) }}
{%- endmacro %}

{% macro rehearsal_raw_table() -%}
    {{ return(rehearsal_raw_schema() ~ '.NORDWIND_ORDERS_RAW') }}
{%- endmacro %}

{% macro rehearsal_source_stage() -%}
    {% set ns = rehearsal_namespace() %}
    {% set stage = env_var('DBT_SOURCE_STAGE') | upper %}
    {% if not modules.re.fullmatch('[A-Z][A-Z0-9_]{0,254}[.][A-Z][A-Z0-9_]{0,254}[.][A-Z][A-Z0-9_]{0,254}', stage) %}
        {{ exceptions.raise_compiler_error('DBT_SOURCE_STAGE must be one existing fully qualified stage, without a path.') }}
    {% endif %}
    {% set parts = stage.split('.') %}
    {% if parts[0] != ns.database %}
        {{ exceptions.raise_compiler_error('The existing fixture stage must be in the selected development database.') }}
    {% endif %}
    {{ return(adapter.quote(parts[0]) ~ '.' ~ adapter.quote(parts[1]) ~ '.' ~ adapter.quote(parts[2])) }}
{%- endmacro %}

{% macro rehearsal_create_raw_schema() -%}
    create schema if not exists {{ rehearsal_raw_schema() }}
{%- endmacro %}

{% macro rehearsal_create_raw_table() -%}
    create table if not exists {{ rehearsal_raw_table() }} (
        order_no varchar, pos varchar, created varchar, customer varchar,
        article varchar, qty varchar, price varchar, discount varchar,
        cur varchar, status varchar, ship_to varchar, exported_at varchar,
        _source_file varchar, _file_row_number number,
        _loaded_at timestamp_ltz default current_timestamp()
    )
{%- endmacro %}

{% macro rehearsal_copy_fixture() -%}
    {% set ns = rehearsal_namespace() %}
    copy into {{ rehearsal_raw_table() }}
        (order_no, pos, created, customer, article, qty, price, discount,
         cur, status, ship_to, exported_at, _source_file, _file_row_number)
    from (
        select $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
            metadata$filename, metadata$file_row_number
        from @{{ rehearsal_source_stage() }}
    )
    files = ('{{ var('fixture_file') }}')
    file_format = (
        type = csv
        record_delimiter = '\n'
        field_delimiter = ','
        skip_header = 1
        field_optionally_enclosed_by = '"'
        escape = none
        escape_unenclosed_field = '\\'
        trim_space = false
        null_if = ('\\N')
        error_on_column_count_mismatch = true
        empty_field_as_null = false
        skip_byte_order_mark = true
        encoding = 'UTF8'
    )
    force = false
{%- endmacro %}
