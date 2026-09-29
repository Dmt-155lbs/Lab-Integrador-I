{#
  Por defecto dbt concatena el esquema del perfil con el de cada modelo
  (ej. SILVER_BRONZE). Esta macro usa el esquema de la capa tal cual,
  para que los modelos queden exactamente en BRONZE, SILVER y GOLD.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
