-- Puts each model in the schema its folder names (staging, intermediate, marts), instead of dbt's default of the
-- target schema joined to it (dbt_staging). One person builds this project, so developers need no schemas of their own.
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
