# Laboratorio Integrador I — Tubería ELT de NYC Yellow Taxi

Tubería **ELT reproducible** que ingiere automáticamente los viajes de **NYC Yellow Taxi** (enero 2025 – agosto 2026), los carga en **Snowflake**, los transforma con **dbt** en una arquitectura **Bronze → Silver → Gold** y publica un **esquema estrella** listo para análisis. Todo se orquesta con **Kestra** sobre **Docker Compose**.

| | |
|---|---|
| Datos cargados | 19 meses publicados (ene-2025 a jul-2026) · **75.089.241** viajes en RAW |
| Agosto 2026 | Aún **no publicado** por la TLC (HTTP 403). El pipeline lo omite sin fallar y lo cargará solo cuando exista (trigger mensual) |
| Gold | `fct_trips` con **73.089.892** viajes válidos + 6 dimensiones |
| Calidad | **79 tests** de dbt (`not_null`, `unique`, `relationships`, `accepted_values` y reconciliaciones entre capas) — todos en verde |
| Idempotencia | Re-ejecutar no duplica en ninguna capa (probado) |

---

## Arquitectura

![Arquitectura](docs/diagramas/arquitectura.png)

Fuente editable: [`docs/diagramas/arquitectura.mmd`](docs/diagramas/arquitectura.mmd).

| Componente | Rol |
|---|---|
| **NYC TLC** | Fuente: un Parquet por mes (`yellow_tripdata_AAAA-MM.parquet`) + tabla de zonas y diccionario de datos |
| **Kestra 1.3.37** (Docker) | Orquestador. Descarga los archivos, los sube a Snowflake y ejecuta dbt. Flows versionados en `kestra/flows/` |
| **Snowflake** | Almacenamiento y cómputo. Objetos aislados con prefijo `LAB_INT_`: base `LAB_INT_NYC_TAXI`, warehouse `LAB_INT_WH` (XS), rol `LAB_INT_ROLE`, usuario de servicio `LAB_INT_SVC` (llave RSA), tope de gasto `LAB_INT_RM` |
| **dbt 1.11** (contenedor lanzado por Kestra) | Transformaciones, documentación y tests |

### Capas

| Esquema | Qué contiene | Cómo se construye |
|---|---|---|
| `RAW` | `YELLOW_TRIPDATA`: los Parquet tal cual + `SOURCE_FILE`, `SOURCE_ROW_NUMBER`, `LOADED_AT` | Kestra: `PUT` al stage interno + `COPY INTO … MATCH_BY_COLUMN_NAME` |
| `BRONZE` | `brz_yellow_tripdata`: mismas columnas y tipos que la fuente + metadata de linaje (archivo, **período de origen**, fila, **fecha de carga**). Seeds oficiales de la TLC | dbt, incremental por archivo |
| `SILVER` | `slv_yellow_trips` (viajes limpios y únicos), `slv_yellow_trips_audit` (veredicto de calidad por fila), `slv_trip_quality_summary` | dbt, tabla |
| `GOLD` | Esquema estrella: `fct_trips` + `dim_date`, `dim_time`, `dim_zone`, `dim_vendor`, `dim_rate_code`, `dim_payment_type` | dbt, tabla |

---

## Esquema estrella (Gold)

![Esquema estrella](docs/diagramas/esquema_estrella.png)

Fuente editable: [`docs/diagramas/esquema_estrella.mmd`](docs/diagramas/esquema_estrella.mmd).

- **Grano de `fct_trips`:** un viaje de taxi amarillo **válido y único** (una fila de `slv_yellow_trips`).
- **PK:** `trip_key` = MD5 de todos los atributos de negocio del viaje.
- **FKs → dimensiones:**

| FK en `fct_trips` | Dimensión (PK) | Perspectiva de análisis |
|---|---|---|
| `pickup_date_key`, `dropoff_date_key` | `dim_date` (`date_key` AAAAMMDD) | Día, mes, trimestre, día de la semana, fin de semana |
| `pickup_time_key`, `dropoff_time_key` | `dim_time` (`time_key` 0–23) | Hora, franja del día, ventana de hora pico |
| `pickup_location_id`, `dropoff_location_id` | `dim_zone` (`location_id`) | Borough, zona, aeropuertos (*role-playing*: recogida y destino) |
| `vendor_id` | `dim_vendor` (`vendor_id`) | Proveedor TPEP |
| `rate_code_id` | `dim_rate_code` (`rate_code_id`) | Tipo de tarifa (estándar, JFK, Newark, negociada…) |
| `payment_type_id` | `dim_payment_type` (`payment_type_id`) | Forma de pago (tarjeta, efectivo, Flex Fare…) |

- **Métricas (aditivas):** `passenger_count`, `trip_distance_miles`, `trip_duration_minutes`, `fare_amount`, `extra_amount`, `mta_tax_amount`, `tip_amount`, `tolls_amount`, `improvement_surcharge_amount`, `congestion_surcharge_amount`, `airport_fee_amount`, `cbd_congestion_fee_amount`, `total_amount`.
- **Atributos degenerados:** `pickup_datetime`, `dropoff_datetime`, `is_store_and_forward`, `request_source`, `source_period`.
- Las dimensiones usan los **códigos oficiales de la TLC** como PK e incluyen miembros "desconocido" (vendor `-1`, tarifa `99`, pago `5`, zona `264`) para que toda FK sea válida.

---

## Estructura del repositorio

```
labs/semana-07/
├── README.md                         ← este archivo
├── docker-compose.yml                ← Kestra + Postgres (infraestructura local)
├── .env.example                      ← plantilla de variables (el .env real NO se sube)
├── .gitignore
├── infra/snowflake/
│   ├── 01_bootstrap.sql              ← infraestructura Snowflake (una vez, con ACCOUNTADMIN)
│   └── 99_reset_datos.sql            ← opcional: vacía las capas para probar desde cero
├── kestra/flows/                     ← código de ingesta y orquestación
│   ├── main_nyc_taxi.pipeline.yml            ← PUNTO DE ENTRADA: ingesta + dbt (programado mensual)
│   ├── main_nyc_taxi.ingest_yellow_taxi.yml  ← crea stage/tabla y recorre los meses
│   ├── main_nyc_taxi.ingest_month.yml        ← carga idempotente de un mes
│   ├── main_nyc_taxi.dbt_build.yml           ← ejecuta dbt en un contenedor
│   └── main_nyc_taxi.test_snowflake.yml      ← prueba de conexión
├── dbt/nyc_taxi/                     ← proyecto dbt
│   ├── dbt_project.yml · profiles.yml (sin secretos, lee variables de entorno)
│   ├── seeds/                        ← zonas, vendors, tarifas y tipos de pago oficiales de la TLC
│   ├── macros/                       ← esquemas exactos, llave sustituta, incremental por archivo
│   ├── models/bronze · silver · gold
│   └── tests/                        ← tests singulares (reconciliación y reglas de negocio)
└── docs/
    ├── GUIA_PASO_A_PASO.md           ← guía completa fase por fase + bitácora de errores
    ├── decisiones_limpieza.md        ← justificación de cada regla de Silver (con números)
    └── diagramas/                    ← arquitectura y esquema estrella (.mmd + .png)
```

---

## Cómo levantar y ejecutar la solución desde cero

### Requisitos

- Docker Desktop (con Docker Compose v2) y Git.
- Una cuenta de Snowflake con acceso a `ACCOUNTADMIN` (solo para el paso 2).
- OpenSSL (en Windows viene con Git: `C:\Program Files\Git\mingw64\bin\openssl.exe`).
- Unos 3 GB libres y conexión a internet (se descargan y suben ~1,3 GB de Parquet).

Los comandos están en PowerShell (Windows). En macOS/Linux son equivalentes; ver las notas.

### 1. Clonar el repo y generar la llave RSA

```powershell
git clone https://github.com/Dmt-155lbs/Lab-Integrador-I.git
```
```powershell
cd Lab-Integrador-I\labs\semana-07
```
```powershell
$openssl = "C:\Program Files\Git\mingw64\bin\openssl.exe"
```
```powershell
& $openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out keys\rsa_key.p8
```
```powershell
& $openssl pkey -in keys\rsa_key.p8 -pubout -out keys\rsa_key.pub
```

Copia la llave pública (sin las líneas `-----BEGIN/END-----`) al portapapeles:

```powershell
(Get-Content keys\rsa_key.pub | Where-Object { $_ -notmatch '-----' }) -join '' | Set-Clipboard
```

> `keys/` está en `.gitignore`: la llave privada nunca se sube.

### 2. Crear la infraestructura en Snowflake (una sola vez)

1. Abre [`infra/snowflake/01_bootstrap.sql`](infra/snowflake/01_bootstrap.sql) en una hoja de **Snowsight** con un usuario que tenga `ACCOUNTADMIN`.
2. Reemplaza `PEGA_AQUI_TU_LLAVE_PUBLICA` por la llave copiada, **manteniendo las comillas simples**.
3. Ejecuta todo con **Run All** (`Ctrl+Shift+Enter`).
4. Anota tu *account identifier*:

```sql
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME();
```

El script es idempotente y solo crea objetos con prefijo `LAB_INT_`, así que no afecta otros proyectos de la cuenta.

### 3. Configurar el `.env`

```powershell
Copy-Item .env.example .env
```

Edita `.env` y completa:

- `SNOWFLAKE_ACCOUNT`: el account identifier del paso 2.
- `KESTRA_ADMIN_PASSWORD`: 8 o más caracteres, con al menos una mayúscula y un número; solo letras y números.
- `SNOWFLAKE_PRIVATE_KEY_B64`: la llave privada en base64, en una sola línea. Cópiala al portapapeles con:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path "keys\rsa_key.p8"))) | Set-Clipboard
```

> macOS/Linux: `base64 < keys/rsa_key.p8 | tr -d '\n'`.

### 4. Levantar la infraestructura local

```powershell
docker compose config --quiet
```
```powershell
docker compose up -d
```
```powershell
docker compose ps
```

- `config --quiet` no debe imprimir nada; si falta una variable, muestra `Falta … en .env`.
- En `ps`, los contenedores `kestra` y `postgres` deben estar `running`/`healthy`.
- Espera entre 30 y 60 s y abre **http://localhost:8090**. Entra con `KESTRA_ADMIN_USER` / `KESTRA_ADMIN_PASSWORD`.
- Kestra carga solo los 5 flows del namespace `nyc_taxi` desde `kestra/flows/`.
- Opcional: ejecuta `nyc_taxi.test_snowflake`. Debe registrar `Conexion OK -> {USUARIO=LAB_INT_SVC, ...}`.

### 5. Ejecutar el pipeline completo

En Kestra: **Flows → `nyc_taxi.pipeline` → Execute** (con `force_reload = false`). El flow hace dos cosas:

1. **`ingest_yellow_taxi`:** crea el file format, el stage y la tabla RAW si no existen, y carga los 20 meses de 2 en 2. Salta los meses que ya están cargados y los que la TLC aún no publicó.
2. **`dbt_build`:** ejecuta `dbt build` (seeds, Bronze, Silver, Gold y los 79 tests) dentro del contenedor `ghcr.io/kestra-io/dbt-snowflake`.

El flow `pipeline` también se ejecuta solo **el día 5 de cada mes a las 06:00** (trigger `monthly`), así que los meses nuevos se incorporan automáticamente.

**Resultado de la ejecución desde cero** (29-sep-2026): Snowflake vacío (`99_reset_datos.sql`) y Kestra recién creado (`docker compose down -v` + `up -d`), ejecutando solo el flow `pipeline`.

| Paso | Estado | Duración | Resultado |
|---|---|---:|---|
| `ingest_yellow_taxi` (20 subflows `ingest_month`) | SUCCESS | 11 min 50 s | 19 meses cargados (75.089.241 filas); 2026-08 omitido con WARN (no publicado) |
| `dbt_build` → `dbt build` | SUCCESS | 4 min 04 s | `PASS=94 WARN=0 ERROR=0`: 4 seeds, 11 modelos, 79 tests |
| **`pipeline` (total)** | **SUCCESS** | **15 min 54 s** | 16 tablas creadas en RAW, BRONZE, SILVER y GOLD |

### 6. Verificar en Snowflake

```sql
USE ROLE LAB_INT_ROLE;
USE WAREHOUSE LAB_INT_WH;
USE DATABASE LAB_INT_NYC_TAXI;

SELECT 'RAW' AS capa, COUNT(*) AS filas FROM RAW.YELLOW_TRIPDATA
UNION ALL SELECT 'BRONZE', COUNT(*) FROM BRONZE.BRZ_YELLOW_TRIPDATA
UNION ALL SELECT 'SILVER', COUNT(*) FROM SILVER.SLV_YELLOW_TRIPS
UNION ALL SELECT 'GOLD fct_trips', COUNT(*) FROM GOLD.FCT_TRIPS;
```

Resultado esperado: RAW = BRONZE = 75.089.241; SILVER = GOLD = 73.089.892.

---

## Idempotencia: re-ejecutar no duplica ni deja inconsistencias

| Capa | Mecanismo | Prueba realizada |
|---|---|---|
| **Ingesta (RAW)** | Cada mes se omite si ya está cargado. Con `force_reload = true` se hace `DELETE` del mes y luego `COPY INTO … FORCE = TRUE`. `PURGE = TRUE` vacía el stage | 2ª ejecución: los 19 meses salieron como "ya está en RAW". Recarga forzada de 2026-07: siguen 3.530.109 filas |
| **Bronze** | Incremental por archivo: solo procesa archivos nuevos o recargados (`LOADED_AT` más reciente) y un `pre_hook` borra esos archivos antes de reinsertarlos | Sin cambios en RAW: inserta 0 filas. Tras recargar 2025-02: reprocesa solo sus 3.577.543 filas y Bronze sigue = RAW |
| **Silver / Gold** | Tablas reconstruidas en cada `dbt build` desde la capa anterior | Tests de reconciliación: RAW = Bronze por archivo; Bronze = válidas + descartadas; Silver = `fct_trips` |

---

## Calidad de datos (Silver)

Las reglas se definieron **perfilando los 75 M de filas**. Justificación completa: [`docs/decisiones_limpieza.md`](docs/decisiones_limpieza.md).

| Dimensión de calidad | Tratamiento |
|---|---|
| **Tipos de datos** | Timestamps a `TIMESTAMP_NTZ` (se carga con `USE_LOGICAL_TYPE`); montos a `NUMBER(12,2)`; códigos a `INTEGER`; flag Y/N a booleano |
| **Nulos** | Los 18,4 M nulos de pasajeros, tarifa, flag y recargos son exactamente los viajes **Flex Fare**: no se eliminan. Tarifa nula → 99 (*unknown* TLC); recargos nulos → 0; pasajeros → `NULL` (no se inventan) |
| **Duplicados** | `trip_id` = MD5 de todos los atributos. Se conserva 1 fila por viaje (hubo 1 duplicado exacto). La idempotencia de ingesta y Bronze evita duplicados técnicos |
| **Registros inválidos** | Se descartan: total negativo (reversos contables, 1,12 M), duración ≤ 0 (874.801), distancia > 500 mi (2.583), duración > 24 h (573), fecha fuera del período del archivo (345), total > 1.000 USD (93) |
| **Nombres y formatos** | `snake_case` descriptivo (`PULocationID` → `pickup_location_id`), sufijo `_amount` y unidad (`_miles`), códigos fuera del diccionario → miembro "desconocido", columna nueva `request_source` (2026-06) normalizada |

Resultado: **73.089.892 viajes válidos (97,34 %)**. El detalle por período y regla está en `SILVER.SLV_TRIP_QUALITY_SUMMARY`.

## Pruebas (dbt tests)

| Tipo | Dónde |
|---|---|
| `not_null` + `unique` | Todas las PK: dimensiones, seeds, `slv_yellow_trips.trip_id`, `fct_trips.trip_key` |
| `relationships` | Las 9 FK de `fct_trips` hacia `dim_date`, `dim_time`, `dim_zone`, `dim_vendor`, `dim_rate_code` y `dim_payment_type` |
| `accepted_values` | Códigos TLC en Silver (vendor, tarifa, pago, pasajeros) y franjas horarias |
| Singulares | Reconciliación RAW↔Bronze (por archivo), Bronze↔Silver, Silver↔Gold, y reglas de negocio de `fct_trips` |

Último `dbt build`: **PASS=94, WARN=0, ERROR=0** (4 seeds, 11 modelos, 79 tests). Un test detectó un bug real en Silver durante el desarrollo; está documentado en la guía.

---

## Consultas de ejemplo

```sql
-- Viajes e ingreso por mes y tipo de pago
SELECT d.year_month, p.payment_type_description,
       COUNT(*) AS viajes, ROUND(SUM(f.total_amount), 2) AS ingreso_usd
FROM GOLD.FCT_TRIPS f
JOIN GOLD.DIM_DATE d          ON f.pickup_date_key = d.date_key
JOIN GOLD.DIM_PAYMENT_TYPE p  ON f.payment_type_id = p.payment_type_id
GROUP BY 1, 2
ORDER BY 1, 3 DESC;

-- Zonas de recogida con más viajes, distancia y duración promedio
SELECT z.borough, z.zone_name, COUNT(*) AS viajes,
       ROUND(AVG(f.trip_distance_miles), 2) AS millas_prom,
       ROUND(AVG(f.trip_duration_minutes), 1) AS minutos_prom
FROM GOLD.FCT_TRIPS f
JOIN GOLD.DIM_ZONE z ON f.pickup_location_id = z.location_id
GROUP BY 1, 2
ORDER BY 3 DESC
LIMIT 10;

-- Demanda y propina promedio por franja del día y fin de semana
SELECT t.day_part, d.is_weekend, COUNT(*) AS viajes, ROUND(AVG(f.tip_amount), 2) AS propina_prom
FROM GOLD.FCT_TRIPS f
JOIN GOLD.DIM_TIME t ON f.pickup_time_key = t.time_key
JOIN GOLD.DIM_DATE d ON f.pickup_date_key = d.date_key
GROUP BY 1, 2
ORDER BY 1, 2;
```

Algunos hallazgos:

- **Upper East Side South, Midtown Center y JFK** son las zonas con más recogidas. Desde JFK los viajes promedian 15 millas y 42 minutos.
- **Los viajes Flex Fare casi se duplicaron**, de 536 mil (enero 2025) a 970 mil (julio 2026).

---

## Operación

| Tarea | Cómo |
|---|---|
| Recargar un mes puntual | Ejecutar `nyc_taxi.ingest_month` con `month = AAAA-MM` y `force_reload = true`, luego `dbt_build` |
| Ejecutar solo una parte de dbt | `nyc_taxi.dbt_build` con `dbt_command`, p. ej. `dbt build --select path:models/silver` o `dbt test` |
| Apagar / encender | `docker compose stop` / `docker compose up -d` (se conserva todo) |
| Probar desde cero | Ejecutar `infra/snowflake/99_reset_datos.sql`, luego `docker compose down -v`, `docker compose up -d` y el flow `pipeline` |
| Editar un flow de Kestra | Editar el `.yml` en `kestra/flows/` y ejecutar `docker compose restart kestra` (en Windows Kestra solo detecta cambios al arrancar). Los flows **no** se editan en la UI |

**Costos:** todo el desarrollo y las pruebas de este laboratorio consumieron **0,93 créditos**. Eso incluye dos cargas completas, recargas de prueba, unos 10 `dbt build` y la ejecución desde cero, todo en el warehouse XS. El resource monitor `LAB_INT_RM` suspende el warehouse si el lab llega a 10 créditos en el mes.

## Documentación

- [`docs/GUIA_PASO_A_PASO.md`](docs/GUIA_PASO_A_PASO.md): cómo se construyó cada fase (qué archivo, qué comando, por qué) y la **bitácora de errores** encontrados y resueltos.
- [`docs/decisiones_limpieza.md`](docs/decisiones_limpieza.md): justificación de la limpieza, con números.
- Diccionario de datos oficial: [TLC Yellow Taxi Data Dictionary (mar-2025)](https://www.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_yellow.pdf).
