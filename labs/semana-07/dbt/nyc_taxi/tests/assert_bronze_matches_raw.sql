-- Reconciliacion RAW -> BRONZE: cada archivo debe tener exactamente las mismas
-- filas en Bronze que en RAW (ni perdidas ni duplicadas por re-ejecuciones).
-- El test falla si devuelve filas.
with raw_counts as (
    select source_file, count(*) as raw_rows
    from {{ source('raw', 'yellow_tripdata') }}
    group by 1
),

bronze_counts as (
    select _source_file as source_file, count(*) as bronze_rows
    from {{ ref('brz_yellow_tripdata') }}
    group by 1
)

select
    coalesce(r.source_file, b.source_file) as source_file,
    r.raw_rows,
    b.bronze_rows
from raw_counts r
full outer join bronze_counts b
    on r.source_file = b.source_file
where coalesce(r.raw_rows, -1) <> coalesce(b.bronze_rows, -1)
