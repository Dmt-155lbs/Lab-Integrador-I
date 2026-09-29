{#
  GOLD · Tabla de hechos de viajes.
  Grano: UN viaje de taxi amarillo valido y unico (una fila de slv_yellow_trips).
  PK: trip_key. FKs hacia dim_date, dim_time (recogida y destino), dim_zone
  (recogida y destino, role-playing), dim_vendor, dim_rate_code, dim_payment_type.
#}
select
    -- ---------- llave primaria ----------
    trip_id                                                  as trip_key,

    -- ---------- llaves foraneas ----------
    to_number(to_char(pickup_datetime, 'YYYYMMDD'))          as pickup_date_key,
    hour(pickup_datetime)                                    as pickup_time_key,
    to_number(to_char(dropoff_datetime, 'YYYYMMDD'))         as dropoff_date_key,
    hour(dropoff_datetime)                                   as dropoff_time_key,
    pickup_location_id,
    dropoff_location_id,
    vendor_id,
    rate_code_id,
    payment_type_id,

    -- ---------- atributos degenerados (propios del viaje) ----------
    pickup_datetime,
    dropoff_datetime,
    is_store_and_forward,
    request_source,
    source_period,

    -- ---------- metricas ----------
    passenger_count,
    trip_distance_miles,
    round(datediff('second', pickup_datetime, dropoff_datetime) / 60, 2)::number(10, 2)
                                                             as trip_duration_minutes,
    fare_amount,
    extra_amount,
    mta_tax_amount,
    tip_amount,
    tolls_amount,
    improvement_surcharge_amount,
    congestion_surcharge_amount,
    airport_fee_amount,
    cbd_congestion_fee_amount,
    total_amount
from {{ ref('slv_yellow_trips') }}
