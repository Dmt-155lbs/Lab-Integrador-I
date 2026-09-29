{#
  SILVER · Auditoria de calidad. Grano: una fila de Bronze (75M+).
  Estandariza TODAS las filas y les asigna un veredicto de calidad:
    - rejection_reason: primera regla de validez que incumple (NULL = valida)
    - duplicate_rank  : 1 = primera aparicion del viaje; >1 = duplicado exacto
  De aqui salen slv_yellow_trips (solo validas y no duplicadas) y
  slv_trip_quality_summary (cuantas filas descarta cada regla).
  Las reglas se justifican en docs/decisiones_limpieza.md.
#}

with bronze as (
    select * from {{ ref('brz_yellow_tripdata') }}
),

standardized as (
    select
        -- ---------- identificador del viaje (hash de los atributos de la fuente) ----------
        {{ surrogate_key([
            'vendorid', 'tpep_pickup_datetime', 'tpep_dropoff_datetime', 'passenger_count',
            'trip_distance', 'ratecodeid', 'store_and_fwd_flag', 'pulocationid', 'dolocationid',
            'payment_type', 'fare_amount', 'extra', 'mta_tax', 'tip_amount', 'tolls_amount',
            'improvement_surcharge', 'total_amount', 'congestion_surcharge', 'airport_fee',
            'cbd_congestion_fee', 'request_source'
        ]) }}                                                         as trip_id,

        -- ---------- codigos: fuera del diccionario TLC -> miembro "desconocido" ----------
        iff(vendorid in (1, 2, 6, 7), vendorid, -1)::integer           as vendor_id,
        coalesce(iff(ratecodeid in (1, 2, 3, 4, 5, 6, 99), ratecodeid, 99), 99)::integer
                                                                       as rate_code_id,
        coalesce(iff(payment_type between 0 and 6, payment_type, 5), 5)::integer
                                                                       as payment_type_id,
        iff(pulocationid between 1 and 265, pulocationid, 264)::integer as pickup_location_id,
        iff(dolocationid between 1 and 265, dolocationid, 264)::integer as dropoff_location_id,

        -- ---------- fechas ----------
        tpep_pickup_datetime::timestamp_ntz                            as pickup_datetime,
        tpep_dropoff_datetime::timestamp_ntz                           as dropoff_datetime,

        -- ---------- atributos ----------
        -- 0 o mas de 6 pasajeros no es posible en un yellow taxi -> desconocido (NULL)
        iff(passenger_count between 1 and 6, passenger_count, null)::integer
                                                                       as passenger_count,
        round(trip_distance, 2)::number(10, 2)                         as trip_distance_miles,
        case upper(trim(store_and_fwd_flag))
            when 'Y' then true
            when 'N' then false
        end                                                            as is_store_and_forward,
        nullif(upper(trim(request_source)), '')                        as request_source,

        -- ---------- montos (USD, 2 decimales); recargos no informados -> 0 ----------
        round(fare_amount, 2)::number(12, 2)                           as fare_amount,
        round(extra, 2)::number(12, 2)                                 as extra_amount,
        round(mta_tax, 2)::number(12, 2)                               as mta_tax_amount,
        round(tip_amount, 2)::number(12, 2)                            as tip_amount,
        round(tolls_amount, 2)::number(12, 2)                          as tolls_amount,
        round(improvement_surcharge, 2)::number(12, 2)                 as improvement_surcharge_amount,
        round(coalesce(congestion_surcharge, 0), 2)::number(12, 2)     as congestion_surcharge_amount,
        round(coalesce(airport_fee, 0), 2)::number(12, 2)              as airport_fee_amount,
        round(coalesce(cbd_congestion_fee, 0), 2)::number(12, 2)       as cbd_congestion_fee_amount,
        round(total_amount, 2)::number(12, 2)                          as total_amount,

        -- ---------- linaje ----------
        _source_file                                                   as source_file,
        _source_period                                                 as source_period,
        _source_row_number                                             as source_row_number,
        _loaded_at                                                     as loaded_at
    from bronze
)

select
    *,
    -- ---------- reglas de validez (se registra la primera que se incumple) ----------
    case
        when date_trunc('month', pickup_datetime)::date <> source_period
            then 'PICKUP_FUERA_DEL_PERIODO'
        when dropoff_datetime <= pickup_datetime
            then 'DURACION_NO_POSITIVA'
        -- en segundos: DATEDIFF('minute') cuenta cambios de minuto, no tiempo
        -- transcurrido (24 h 49 s daba 1440 y se colaba; lo detecto un test)
        when datediff('second', pickup_datetime, dropoff_datetime) > 86400
            then 'DURACION_MAYOR_24H'
        when total_amount < 0
            then 'TOTAL_NEGATIVO'
        when total_amount > 1000
            then 'TOTAL_ATIPICO'
        when trip_distance_miles > 500
            then 'DISTANCIA_ATIPICA'
    end                                                                as rejection_reason,
    -- ---------- duplicados exactos: se conserva la carga mas reciente ----------
    row_number() over (
        partition by trip_id
        order by loaded_at desc, source_row_number
    )                                                                  as duplicate_rank
from standardized
