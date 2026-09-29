-- Reconciliacion BRONZE -> SILVER: toda fila de Bronze termina clasificada
-- (valida, descartada por una regla o duplicada) y Silver contiene exactamente
-- las filas VALIDO del resumen de calidad. El test falla si devuelve filas.
with bronze as (
    select count(*) as n from {{ ref('brz_yellow_tripdata') }}
),

summary as (
    select
        sum(row_count)                                        as total_clasificado,
        sum(iff(quality_result = 'VALIDO', row_count, 0))     as validos
    from {{ ref('slv_trip_quality_summary') }}
),

silver as (
    select count(*) as n from {{ ref('slv_yellow_trips') }}
)

select
    bronze.n                 as filas_bronze,
    summary.total_clasificado,
    summary.validos,
    silver.n                 as filas_silver
from bronze, summary, silver
where bronze.n <> summary.total_clasificado
   or summary.validos <> silver.n
