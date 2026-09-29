{#
  GOLD · Dimension tarifa (RatecodeID). Grano: un codigo de tarifa.
  PK: rate_code_id. El codigo 99 (Null/unknown) de la TLC recibe los nulos
  y los codigos no documentados (ver slv_yellow_trips).
#}
select
    rate_code_id,
    rate_code_description,
    rate_code_id in (2, 3)  as is_airport_rate
from {{ ref('tlc_rate_codes') }}
