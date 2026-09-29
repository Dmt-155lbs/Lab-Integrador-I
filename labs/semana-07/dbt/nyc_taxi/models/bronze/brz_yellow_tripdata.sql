{#
  BRONZE · NYC Yellow Taxi lo mas cercano posible a la fuente.
  - Mismas columnas, nombres y tipos que el Parquet original (sin limpiar).
  - Agrega metadata de linaje: archivo y periodo de origen, fila y fecha de carga.
  - Incremental por ARCHIVO: solo procesa archivos nuevos o recargados en RAW.
    El pre_hook borra de Bronze esos archivos antes de reinsertarlos, asi una
    recarga reemplaza el mes completo y re-ejecutar nunca duplica filas.
#}
{{ config(
    materialized = 'incremental',
    incremental_strategy = 'append',
    on_schema_change = 'append_new_columns',
    pre_hook = "{% if is_incremental() %}
                  delete from {{ this }}
                  where _source_file in ({{ changed_source_files(source('raw', 'yellow_tripdata'), this) }})
                {% endif %}"
) }}

select
    -- ----- columnas originales de la TLC (sin transformar) -----
    vendorid,
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    passenger_count,
    trip_distance,
    ratecodeid,
    store_and_fwd_flag,
    pulocationid,
    dolocationid,
    payment_type,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    total_amount,
    congestion_surcharge,
    airport_fee,
    cbd_congestion_fee,
    request_source,

    -- ----- metadata de linaje -----
    source_file                                                    as _source_file,
    to_date(regexp_substr(source_file, '[0-9]{4}-[0-9]{2}') || '-01') as _source_period,
    source_row_number                                              as _source_row_number,
    loaded_at                                                      as _loaded_at,
    current_timestamp()                                            as _bronze_processed_at

from {{ source('raw', 'yellow_tripdata') }}

{% if is_incremental() %}
where source_file in ({{ changed_source_files(source('raw', 'yellow_tripdata'), this) }})
{% endif %}
