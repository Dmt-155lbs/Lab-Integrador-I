{#
  Devuelve los archivos de RAW que Bronze todavia no tiene, o que fueron
  recargados en RAW despues de su ultima carga en Bronze (LOADED_AT mayor).
  La usa brz_yellow_tripdata para procesar SOLO lo nuevo/recargado y
  reemplazar esos archivos completos -> re-ejecutar nunca duplica filas.
#}
{% macro changed_source_files(source_relation, target_relation) %}
    select r.source_file
    from (
        select source_file, max(loaded_at) as max_loaded_at
        from {{ source_relation }}
        group by source_file
    ) r
    left join (
        select _source_file, max(_loaded_at) as max_loaded_at
        from {{ target_relation }}
        group by _source_file
    ) b
        on b._source_file = r.source_file
    where b._source_file is null
       or r.max_loaded_at > b.max_loaded_at
{% endmacro %}
