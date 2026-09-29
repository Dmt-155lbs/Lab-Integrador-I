{#
  GOLD · Dimension proveedor TPEP (VendorID). Grano: un proveedor.
  PK: vendor_id. Incluye el miembro -1 "Desconocido" para codigos no
  documentados por la TLC, asi toda FK de la tabla de hechos es valida.
#}
select vendor_id, vendor_name
from {{ ref('tlc_vendors') }}

union all

select -1, 'Desconocido (codigo no documentado)'
