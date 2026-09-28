
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS LAB_INT_ROLE
  COMMENT = 'Lab Integrador I: ingesta (Kestra) y transformacion (dbt)';

-- Jerarquia recomendada: SYSADMIN hereda los privilegios del rol del lab
GRANT ROLE LAB_INT_ROLE TO ROLE SYSADMIN;

-- Tu usuario personal tambien lo recibe (para explorar datos en Snowsight)
SET my_user = CURRENT_USER();
GRANT ROLE LAB_INT_ROLE TO USER IDENTIFIER($my_user);

-- ---------------------------------------------------------------------
-- 2. Warehouse dedicado
--    XSMALL = 1 credito/hora. Se suspende solo tras 60 s sin uso.
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS LAB_INT_WH
  WAREHOUSE_SIZE      = 'XSMALL'
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Lab Integrador I: computo dedicado';

GRANT USAGE, OPERATE, MONITOR ON WAREHOUSE LAB_INT_WH TO ROLE LAB_INT_ROLE;

-- ---------------------------------------------------------------------
-- 3. Base de datos
--    La crea SYSADMIN y se la entrega al rol del lab, para que dbt
--    pueda crear y reemplazar tablas/vistas sin problemas de permisos.
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS LAB_INT_NYC_TAXI
  COMMENT = 'Lab Integrador I: NYC Yellow Taxi (RAW > BRONZE > SILVER > GOLD)';

GRANT OWNERSHIP ON DATABASE LAB_INT_NYC_TAXI TO ROLE LAB_INT_ROLE COPY CURRENT GRANTS;

-- ---------------------------------------------------------------------
-- 4. Esquemas (arquitectura medallon)
--    Los crea el propio rol del lab -> queda como dueno.
-- ---------------------------------------------------------------------
USE ROLE LAB_INT_ROLE;
USE DATABASE LAB_INT_NYC_TAXI;

CREATE SCHEMA IF NOT EXISTS RAW    COMMENT = 'Aterrizaje: Parquet cargados tal cual con COPY INTO';
CREATE SCHEMA IF NOT EXISTS BRONZE COMMENT = 'dbt: cercano a la fuente + metadata de origen y carga';
CREATE SCHEMA IF NOT EXISTS SILVER COMMENT = 'dbt: datos limpios y estandarizados';
CREATE SCHEMA IF NOT EXISTS GOLD   COMMENT = 'dbt: esquema estrella para analisis';

-- ---------------------------------------------------------------------
-- 5. Usuario de servicio para Kestra y dbt
--    TYPE = SERVICE: no puede entrar con contrasena, solo con llave RSA.
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;

CREATE USER IF NOT EXISTS LAB_INT_SVC
  TYPE              = SERVICE
  DEFAULT_ROLE      = LAB_INT_ROLE
  DEFAULT_WAREHOUSE = LAB_INT_WH
  DEFAULT_NAMESPACE = LAB_INT_NYC_TAXI.RAW
  COMMENT = 'Lab Integrador I: usuario tecnico de Kestra y dbt';

-- Va en un ALTER aparte para poder rotar la llave re-ejecutando el script
ALTER USER LAB_INT_SVC SET RSA_PUBLIC_KEY = 'PEGA_AQUI_TU_LLAVE_PUBLICA';

GRANT ROLE LAB_INT_ROLE TO USER LAB_INT_SVC;

-- ---------------------------------------------------------------------
-- 6. Tope de gasto: si el lab consume 10 creditos en el mes,
--    el warehouse se suspende. Te protege de un error costoso.
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE RESOURCE MONITOR IF NOT EXISTS LAB_INT_RM
  WITH CREDIT_QUOTA    = 10
       FREQUENCY       = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
       TRIGGERS ON 80  PERCENT DO NOTIFY
                ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE LAB_INT_WH SET RESOURCE_MONITOR = LAB_INT_RM;