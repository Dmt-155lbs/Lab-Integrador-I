{#
  GOLD · Dimension tipo de pago. Grano: un tipo de pago.
  PK: payment_type_id. El codigo 5 (Unknown) de la TLC recibe los nulos
  y los codigos no documentados (ver slv_yellow_trips).
#}
select
    payment_type_id,
    payment_type_description,
    payment_type_id in (0, 1, 2) as is_paid_trip   -- flex fare, tarjeta o efectivo
from {{ ref('tlc_payment_types') }}
