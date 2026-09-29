-- =====================================================================
-- Lab Integrador I · NYC Yellow Taxi
-- infra/snowflake/99_reset_datos.sql
--
-- OPCIONAL. Vacia las capas de datos para probar el pipeline desde cero:
-- recrea VACIOS los esquemas RAW, BRONZE, SILVER y GOLD (borra tablas,
-- stage y file format). NO toca la infraestructura del 01_bootstrap.sql
-- (rol, warehouse, base de datos, usuario, resource monitor).
-- Se ejecuta en Snowsight con el rol del lab. Despues basta con ejecutar
-- el flow "pipeline" en Kestra para reconstruir todo.
-- =====================================================================
USE ROLE LAB_INT_ROLE;
USE DATABASE LAB_INT_NYC_TAXI;

CREATE OR REPLACE SCHEMA RAW    COMMENT = 'Aterrizaje: Parquet cargados tal cual con COPY INTO';
CREATE OR REPLACE SCHEMA BRONZE COMMENT = 'dbt: cercano a la fuente + metadata de origen y carga';
CREATE OR REPLACE SCHEMA SILVER COMMENT = 'dbt: datos limpios y estandarizados';
CREATE OR REPLACE SCHEMA GOLD   COMMENT = 'dbt: esquema estrella para analisis'
