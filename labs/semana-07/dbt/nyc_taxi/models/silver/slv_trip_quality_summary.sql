{#
  SILVER · Resumen de calidad. Grano: periodo x resultado.
  Cuantas filas de Bronze quedaron validas, cuantas se descartaron por cada
  regla y cuantas eran duplicados. Sirve para justificar la limpieza.
#}
select
    source_period,
    case
        when rejection_reason is not null then rejection_reason
        when duplicate_rank > 1           then 'DUPLICADO_EXACTO'
        else 'VALIDO'
    end             as quality_result,
    count(*)        as row_count
from {{ ref('slv_yellow_trips_audit') }}
group by 1, 2
