{#
  Genera una llave sustituta (MD5) a partir de una lista de columnas.
  Los NULL se reemplazan por un marcador para que (1, NULL) y (NULL, 1)
  produzcan hashes distintos. Equivalente a dbt_utils.generate_surrogate_key,
  sin depender de paquetes externos.
#}
{% macro surrogate_key(columns) -%}
    md5(concat_ws('|'
    {%- for col in columns %},
        coalesce(to_varchar({{ col }}), '_null_')
    {%- endfor %}
    ))
{%- endmacro %}
