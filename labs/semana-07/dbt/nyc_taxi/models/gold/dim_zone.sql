{#
  GOLD · Dimension zona de taxi (TLC Taxi Zones). Grano: una zona.
  PK: location_id. Se usa dos veces en la tabla de hechos (role-playing):
  zona de recogida y zona de destino.
#}
select
    locationid::integer                                         as location_id,
    borough,
    zone                                                        as zone_name,
    service_zone,
    zone in ('JFK Airport', 'LaGuardia Airport', 'Newark Airport') as is_airport,
    locationid in (264, 265)                                    as is_unknown_zone
from {{ ref('taxi_zone_lookup') }}
