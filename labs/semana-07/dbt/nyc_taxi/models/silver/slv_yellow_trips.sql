{#
  SILVER · Viajes limpios y estandarizados.
  Grano: un viaje valido y unico (trip_id).
  = filas de slv_yellow_trips_audit sin regla incumplida y sin duplicados.
#}
select
    trip_id,
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    passenger_count,
    trip_distance_miles,
    rate_code_id,
    is_store_and_forward,
    pickup_location_id,
    dropoff_location_id,
    payment_type_id,
    request_source,
    fare_amount,
    extra_amount,
    mta_tax_amount,
    tip_amount,
    tolls_amount,
    improvement_surcharge_amount,
    congestion_surcharge_amount,
    airport_fee_amount,
    cbd_congestion_fee_amount,
    total_amount,
    source_file,
    source_period,
    loaded_at
from {{ ref('slv_yellow_trips_audit') }}
where rejection_reason is null
  and duplicate_rank = 1
