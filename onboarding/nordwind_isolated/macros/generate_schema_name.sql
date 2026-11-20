{% macro generate_schema_name(custom_schema_name, node) -%}
    {% set ns = rehearsal_namespace() %}
    {% set default_test_audit = node.resource_type == 'test' and (custom_schema_name | default('', true) | trim | upper) == 'DBT_TEST__AUDIT' %}
    {% if custom_schema_name is not none and (custom_schema_name | trim | upper) != ns.output_schema and not default_test_audit %}
        {{ exceptions.raise_compiler_error('Custom output schemas are not allowed in this rehearsal.') }}
    {% endif %}
    {{ return(ns.output_schema) }}
{%- endmacro %}

{% macro generate_database_name(custom_database_name, node) -%}
    {% set ns = rehearsal_namespace() %}
    {% if custom_database_name is not none and (custom_database_name | trim | upper) != ns.database %}
        {{ exceptions.raise_compiler_error('Custom output databases are not allowed in this rehearsal.') }}
    {% endif %}
    {{ return(ns.database) }}
{%- endmacro %}
