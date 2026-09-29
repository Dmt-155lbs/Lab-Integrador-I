-- Reglas de negocio de la tabla de hechos (deben cumplirse tras la limpieza):
--   * la duracion es positiva y no supera 24 h
--   * el monto total esta entre 0 y 1.000 USD
--   * la distancia no supera 500 millas
--   * los pasajeros, si se informan, estan entre 1 y 6
-- El test falla si devuelve filas.
select
    trip_key,
    trip_duration_minutes,
    total_amount,
    trip_distance_miles,
    passenger_count
from {{ ref('fct_trips') }}
where trip_duration_minutes <= 0
   or trip_duration_minutes > 1440
   or total_amount < 0
   or total_amount > 1000
   or trip_distance_miles > 500
   or (passenger_count is not null and passenger_count not between 1 and 6)
