# Decisiones de limpieza — capa Silver

Este documento justifica cada regla aplicada en la capa Silver. Las reglas se definieron **después de perfilar los 75.089.241 registros cargados en RAW** (19 meses, ene-2025 a jul-2026), no a priori. Los números provienen de la tabla `SILVER.SLV_TRIP_QUALITY_SUMMARY`, que dbt reconstruye en cada ejecución.

Modelos involucrados:

| Modelo | Grano | Rol |
|---|---|---|
| `slv_yellow_trips_audit` | una fila de Bronze | Estandariza **todas** las filas y registra su veredicto (`rejection_reason`, `duplicate_rank`) |
| `slv_yellow_trips` | un viaje válido y único | Tabla limpia (fuente de Gold) = filas sin regla incumplida y `duplicate_rank = 1` |
| `slv_trip_quality_summary` | período × resultado | Cuántas filas deja o descarta cada regla |

Fuente de los códigos: [Data Dictionary – Yellow Taxi Trip Records (TLC, 18-mar-2025)](https://www.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_yellow.pdf).

---

## Resultado global

| Resultado | Filas | % |
|---|---:|---:|
| **VALIDO** | **73.089.893** | **97,337 %** |
| TOTAL_NEGATIVO | 1.120.953 | 1,493 % |
| DURACION_NO_POSITIVA | 874.801 | 1,165 % |
| DISTANCIA_ATIPICA | 2.583 | 0,003 % |
| DURACION_MAYOR_24H | 572 | 0,001 % |
| PICKUP_FUERA_DEL_PERIODO | 345 | < 0,001 % |
| TOTAL_ATIPICO | 93 | < 0,001 % |
| DUPLICADO_EXACTO | 1 | < 0,001 % |
| **Total Bronze** | **75.089.241** | 100 % |

Cada fila descartada se cuenta **una sola vez**, en la primera regla que incumple (el orden de la tabla de reglas de abajo).

---

## 1. Tipos de datos

| Decisión | Por qué |
|---|---|
| Timestamps a `TIMESTAMP_NTZ` | La TLC publica hora local de NY sin zona horaria. Se cargan con `USE_LOGICAL_TYPE = TRUE` para que Snowflake respete el tipo lógico del Parquet (si no, llegan como enteros de microsegundos). |
| Montos a `NUMBER(12,2)` redondeados a 2 decimales | Son dólares; `FLOAT` introduce errores de redondeo al sumar millones de filas. |
| Distancia a `NUMBER(10,2)` (millas) | Misma razón; 2 decimales es la precisión del taxímetro. |
| Códigos (`vendor_id`, `rate_code_id`, `payment_type_id`, zonas) a `INTEGER` | Son identificadores categóricos, no medidas. |
| `store_and_fwd_flag` (`'Y'`/`'N'`) a booleano `is_store_and_forward` | Semántica clara y consistente. |

## 2. Nombres y formatos inconsistentes

| Problema en la fuente | Decisión |
|---|---|
| Mezcla de estilos: `VendorID`, `PULocationID`, `tpep_pickup_datetime`, `Airport_fee` | Todo a `snake_case` descriptivo: `vendor_id`, `pickup_location_id`, `pickup_datetime`, `airport_fee_amount`. |
| Montos sin sufijo uniforme (`extra`, `mta_tax`) | Sufijo `_amount` en todos los montos. |
| Distancia sin unidad | `trip_distance_miles`. |
| `request_source` con espacios o vacío | `UPPER(TRIM())` y cadena vacía → `NULL`. |
| Columna nueva `request_source` desde 2026-06 (*schema drift*) | Se absorbe en la ingesta (`MATCH_BY_COLUMN_NAME`) y queda `NULL` en los meses anteriores. |

## 3. Valores nulos

El perfilado mostró que **todos** los nulos de `passenger_count`, `RatecodeID`, `store_and_fwd_flag`, `congestion_surcharge` y `airport_fee` (18.407.401 filas cada uno) corresponden exactamente a los viajes **Flex Fare (`payment_type = 0`)**, que la TLC registra con un esquema reducido. No son errores: son viajes reales con campos no informados. Por eso **no se eliminan**; se tratan así:

| Columna | Tratamiento | Justificación |
|---|---|---|
| `passenger_count` | Se deja `NULL` | Imputar un número inventaría datos y sesgaría el promedio de pasajeros. |
| `rate_code_id` | `NULL` → **99** | El diccionario TLC define 99 = *Null/unknown*; así la FK hacia `dim_rate_code` siempre es válida. |
| `is_store_and_forward` | Se deja `NULL` | No hay forma de saber si el viaje se almacenó; `NULL` = no informado. |
| `congestion_surcharge_amount`, `airport_fee_amount`, `cbd_congestion_fee_amount` | `NULL` → **0** | Son recargos aditivos: no informado equivale a no cobrado en ese registro, y 0 permite sumarlos sin perder filas. |
| `request_source` | Se deja `NULL` | El campo no existía antes de 2026-06. |

## 4. Valores fuera de dominio (se corrigen, no se eliminan)

| Regla | Filas afectadas en RAW | Tratamiento |
|---|---:|---|
| `passenger_count` = 0 o > 6 | 343.943 (0) + 170 (7–9) | → `NULL` (un yellow taxi lleva de 1 a 6 pasajeros; 0 es un error de captura). |
| `vendor_id` fuera de {1, 2, 6, 7} | 0 | → −1 "Desconocido" (regla defensiva para meses futuros). |
| `rate_code_id` fuera del diccionario | 0 | → 99 (defensiva). |
| `payment_type` fuera de 0–6 | 0 | → 5 *Unknown* (defensiva). |
| Zona fuera de 1–265 | 0 | → 264 *Unknown* (defensiva). |

## 5. Registros inválidos (se descartan)

| # | Regla | Condición | Filas | Justificación |
|---|---|---|---:|---|
| 1 | `PICKUP_FUERA_DEL_PERIODO` | El mes de recogida ≠ mes del archivo | 345 | Fechas imposibles (hasta el año 2001) dentro de archivos de 2025–2026: error del reloj del taxímetro. |
| 2 | `DURACION_NO_POSITIVA` | `dropoff <= pickup` | 874.801 | Un viaje no puede terminar antes o en el mismo segundo en que empieza; no permite calcular duración ni velocidad. El 85 % son de tarjeta de crédito; probablemente son transacciones canceladas o de prueba. |
| 3 | `DURACION_MAYOR_24H` | Duración > 1.440 min | 572 | Taxímetro olvidado encendido. El percentil 99 de la duración es de 72 min. |
| 4 | `TOTAL_NEGATIVO` | `total_amount < 0` | 1.120.953 | Son **reversos contables** (disputas, anulaciones, reembolsos), no viajes: 849.370 tienen un "espejo" positivo idéntico con el mismo vendor, horas y zonas. Se conservan los viajes originales positivos. |
| 5 | `TOTAL_ATIPICO` | `total_amount > 1.000 USD` | 93 | El percentil 99,9 es de 180 USD; hay totales de hasta 863.380 USD, que son errores de captura. |
| 6 | `DISTANCIA_ATIPICA` | `trip_distance > 500 millas` | 2.583 | Hay distancias de hasta 397.994 millas (error de odómetro/GPS). El percentil 99 es de 19,5 millas. |

**Qué NO se descarta, a propósito:**

- **Viajes con distancia 0** (≈2,2 M): pueden ser tarifas fijas o negociadas (por ejemplo, Flex Fare) y tienen monto real.
- **`fare_amount` negativo con `total_amount` ≥ 0** (1,88 M, casi todos Flex Fare): en Flex Fare el precio lo fija el total y `fare_amount` actúa como ajuste. Descartarlos eliminaría viajes reales.
- **`total_amount` distinto de la suma de sus componentes:** en millones de filas no cuadra por reglas tarifarias (Flex Fare, recargos no desglosados). Se usa `total_amount` tal como lo reporta la TLC.

## 6. Duplicados

- **Definición:** dos filas son el mismo viaje si coinciden en **todos** sus atributos de negocio (vendor, horas, pasajeros, distancia, códigos, zonas y los 10 montos).
- **Identificador:** `trip_id = MD5(todos esos atributos)`, generado por la macro `surrogate_key`.
- **Regla:** ante duplicados se conserva la fila de la carga más reciente (`ROW_NUMBER() ... ORDER BY loaded_at DESC`).
- **Resultado:** 1 duplicado exacto en 75 M de filas. `trip_id` queda único en Silver (lo verifica un test `unique`).
- **Duplicados técnicos por recargar la misma fuente:** están cubiertos antes, en la ingesta (DELETE del mes + COPY) y en Bronze (reemplazo por archivo).

## 7. Por qué Silver se reconstruye completa

`slv_yellow_trips_audit` y `slv_yellow_trips` son tablas que dbt **reconstruye en cada ejecución** a partir de Bronze. El cálculo de duplicados es global (entre meses), así que reconstruir garantiza que las reglas se aplican igual a todos los datos y que re-ejecutar el pipeline nunca deja inconsistencias. En un warehouse XSMALL la reconstrucción de las 75 M de filas tarda unos 3 minutos.
