CREATE OR REPLACE PROCEDURE `sing1261.ali1_raw.sp_etl_raw`()
BEGIN

  -- Tabla de control para la capa raw (autocontenida)
  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.etl_control`
  (
    tabla_destino      STRING    NOT NULL,
    archivo_origen     STRING    NOT NULL,
    fecha_particion    DATE,
    tipo               STRING    NOT NULL,
    estado             STRING    NOT NULL,
    registros_cargados INT64,
    mensaje_error      STRING,
    fecha_carga        TIMESTAMP NOT NULL
  );

-- ============================================================
-- SECCIÓN 1: EXTERNAL TABLES
-- Se recrean en cada ejecución para apuntar siempre a GCS actual
-- ============================================================

-- Transaccionales: un solo * para la carpeta de fecha (BigQuery no soporta múltiples *)
CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_ventas`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/ventas/*/ventas_alicorp.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_pedidos`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/pedidos/*/pedidos_alicorp.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_devoluciones`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/devoluciones/*/devoluciones_alicorp.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_fill_rate`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/fill_rate/*/fill_rate_despachos.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_inventario`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/inventario/*/inventario_alicorp.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_metas`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/metas/*/metas_comerciales_raw.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_promociones`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/promociones/*/promociones_alicorp.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_inversion_promocional`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/inversion_promocional/*/inversion_promocional_soles.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_metas_operativas`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/metas_operativas/*/metas_operativas_raw.csv'], skip_leading_rows=1);

-- Maestros: URI exacta, un solo archivo por fuente
CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_clientes`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/clientes/clientes_alicorp.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_productos`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/productos/productos_alicorp.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_canal`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/canal/canal.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_geografia`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/geografia/geografia.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_almacen`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/almacen/almacen.csv'], skip_leading_rows=1);

CREATE OR REPLACE EXTERNAL TABLE `sing1261.ali1_raw.ext_vendedor`
OPTIONS (format='CSV', uris=['gs://ali1_bucket/raw/vendedor/vendedor.csv'], skip_leading_rows=1);


-- ============================================================
-- SECCIÓN 2: TRANSACCIONALES (carga incremental por partición)
-- Cada bloque: crea tabla si no existe → inserta nuevas particiones
--              → registra éxito en control
-- EXCEPTION: registra error y continúa con la siguiente tabla
-- ============================================================

-- === VENTAS ===
BEGIN
  DECLARE rows_loaded INT64 DEFAULT 0;

  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.ventas`
  PARTITION BY fecha_carga
  AS SELECT *, CAST(NULL AS DATE) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_ventas` WHERE FALSE;

  INSERT INTO `sing1261.ali1_raw.ventas`
  SELECT
    *,
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_ventas`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'ventas' AND estado = 'EXITOSO'
    );

  SET rows_loaded = @@row_count;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  SELECT DISTINCT
    'ventas',
    REGEXP_EXTRACT(_FILE_NAME, r'(gs://[^\s]+)'),
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')),
    'INCREMENTAL', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM `sing1261.ali1_raw.ext_ventas`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'ventas' AND estado = 'EXITOSO'
    );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('ventas', 'gs://ali1_bucket/raw/ventas/', CAST(NULL AS DATE), 'INCREMENTAL', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === PEDIDOS ===
BEGIN
  DECLARE rows_loaded INT64 DEFAULT 0;

  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.pedidos`
  PARTITION BY fecha_carga
  AS SELECT *, CAST(NULL AS DATE) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_pedidos` WHERE FALSE;

  INSERT INTO `sing1261.ali1_raw.pedidos`
  SELECT
    *,
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_pedidos`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'pedidos' AND estado = 'EXITOSO'
    );

  SET rows_loaded = @@row_count;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  SELECT DISTINCT
    'pedidos',
    REGEXP_EXTRACT(_FILE_NAME, r'(gs://[^\s]+)'),
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')),
    'INCREMENTAL', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM `sing1261.ali1_raw.ext_pedidos`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'pedidos' AND estado = 'EXITOSO'
    );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('pedidos', 'gs://ali1_bucket/raw/pedidos/', CAST(NULL AS DATE), 'INCREMENTAL', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === DEVOLUCIONES ===
BEGIN
  DECLARE rows_loaded INT64 DEFAULT 0;

  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.devoluciones`
  PARTITION BY fecha_carga
  AS SELECT *, CAST(NULL AS DATE) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_devoluciones` WHERE FALSE;

  INSERT INTO `sing1261.ali1_raw.devoluciones`
  SELECT
    *,
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_devoluciones`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'devoluciones' AND estado = 'EXITOSO'
    );

  SET rows_loaded = @@row_count;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  SELECT DISTINCT
    'devoluciones',
    REGEXP_EXTRACT(_FILE_NAME, r'(gs://[^\s]+)'),
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')),
    'INCREMENTAL', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM `sing1261.ali1_raw.ext_devoluciones`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'devoluciones' AND estado = 'EXITOSO'
    );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('devoluciones', 'gs://ali1_bucket/raw/devoluciones/', CAST(NULL AS DATE), 'INCREMENTAL', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === FILL_RATE ===
BEGIN
  DECLARE rows_loaded INT64 DEFAULT 0;

  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.fill_rate`
  PARTITION BY fecha_carga
  AS SELECT *, CAST(NULL AS DATE) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_fill_rate` WHERE FALSE;

  INSERT INTO `sing1261.ali1_raw.fill_rate`
  SELECT
    *,
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_fill_rate`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'fill_rate' AND estado = 'EXITOSO'
    );

  SET rows_loaded = @@row_count;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  SELECT DISTINCT
    'fill_rate',
    REGEXP_EXTRACT(_FILE_NAME, r'(gs://[^\s]+)'),
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')),
    'INCREMENTAL', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM `sing1261.ali1_raw.ext_fill_rate`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'fill_rate' AND estado = 'EXITOSO'
    );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('fill_rate', 'gs://ali1_bucket/raw/fill_rate/', CAST(NULL AS DATE), 'INCREMENTAL', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === INVENTARIO ===
BEGIN
  DECLARE rows_loaded INT64 DEFAULT 0;

  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.inventario`
  PARTITION BY fecha_carga
  AS SELECT *, CAST(NULL AS DATE) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_inventario` WHERE FALSE;

  INSERT INTO `sing1261.ali1_raw.inventario`
  SELECT
    *,
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_inventario`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'inventario' AND estado = 'EXITOSO'
    );

  SET rows_loaded = @@row_count;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  SELECT DISTINCT
    'inventario',
    REGEXP_EXTRACT(_FILE_NAME, r'(gs://[^\s]+)'),
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')),
    'INCREMENTAL', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM `sing1261.ali1_raw.ext_inventario`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'inventario' AND estado = 'EXITOSO'
    );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('inventario', 'gs://ali1_bucket/raw/inventario/', CAST(NULL AS DATE), 'INCREMENTAL', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === METAS ===
BEGIN
  DECLARE rows_loaded INT64 DEFAULT 0;

  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.metas`
  PARTITION BY fecha_carga
  AS SELECT *, CAST(NULL AS DATE) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_metas` WHERE FALSE;

  INSERT INTO `sing1261.ali1_raw.metas`
  SELECT
    *,
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_metas`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'metas' AND estado = 'EXITOSO'
    );

  SET rows_loaded = @@row_count;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  SELECT DISTINCT
    'metas',
    REGEXP_EXTRACT(_FILE_NAME, r'(gs://[^\s]+)'),
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')),
    'INCREMENTAL', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM `sing1261.ali1_raw.ext_metas`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'metas' AND estado = 'EXITOSO'
    );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('metas', 'gs://ali1_bucket/raw/metas/', CAST(NULL AS DATE), 'INCREMENTAL', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === PROMOCIONES ===
BEGIN
  DECLARE rows_loaded INT64 DEFAULT 0;

  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.promociones`
  PARTITION BY fecha_carga
  AS SELECT *, CAST(NULL AS DATE) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_promociones` WHERE FALSE;

  INSERT INTO `sing1261.ali1_raw.promociones`
  SELECT
    *,
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_promociones`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'promociones' AND estado = 'EXITOSO'
    );

  SET rows_loaded = @@row_count;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  SELECT DISTINCT
    'promociones',
    REGEXP_EXTRACT(_FILE_NAME, r'(gs://[^\s]+)'),
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')),
    'INCREMENTAL', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM `sing1261.ali1_raw.ext_promociones`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'promociones' AND estado = 'EXITOSO'
    );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('promociones', 'gs://ali1_bucket/raw/promociones/', CAST(NULL AS DATE), 'INCREMENTAL', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === INVERSION_PROMOCIONAL ===
BEGIN
  DECLARE rows_loaded INT64 DEFAULT 0;

  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.inversion_promocional`
  PARTITION BY fecha_carga
  AS SELECT *, CAST(NULL AS DATE) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_inversion_promocional` WHERE FALSE;

  INSERT INTO `sing1261.ali1_raw.inversion_promocional`
  SELECT
    *,
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_inversion_promocional`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'inversion_promocional' AND estado = 'EXITOSO'
    );

  SET rows_loaded = @@row_count;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  SELECT DISTINCT
    'inversion_promocional',
    REGEXP_EXTRACT(_FILE_NAME, r'(gs://[^\s]+)'),
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')),
    'INCREMENTAL', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM `sing1261.ali1_raw.ext_inversion_promocional`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'inversion_promocional' AND estado = 'EXITOSO'
    );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('inversion_promocional', 'gs://ali1_bucket/raw/inversion_promocional/', CAST(NULL AS DATE), 'INCREMENTAL', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === METAS_OPERATIVAS ===
BEGIN
  DECLARE rows_loaded INT64 DEFAULT 0;

  CREATE TABLE IF NOT EXISTS `sing1261.ali1_raw.metas_operativas`
  PARTITION BY fecha_carga
  AS SELECT *, CAST(NULL AS DATE) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_metas_operativas` WHERE FALSE;

  INSERT INTO `sing1261.ali1_raw.metas_operativas`
  SELECT
    *,
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) AS fecha_carga
  FROM `sing1261.ali1_raw.ext_metas_operativas`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'metas_operativas' AND estado = 'EXITOSO'
    );

  SET rows_loaded = @@row_count;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  SELECT DISTINCT
    'metas_operativas',
    REGEXP_EXTRACT(_FILE_NAME, r'(gs://[^\s]+)'),
    PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')),
    'INCREMENTAL', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  FROM `sing1261.ali1_raw.ext_metas_operativas`
  WHERE _FILE_NAME LIKE '%.csv'
    AND PARSE_DATE('%Y%m%d', REGEXP_EXTRACT(_FILE_NAME, r'/(\d{8})/')) NOT IN (
      SELECT fecha_particion FROM `sing1261.ali1_raw.etl_control`
      WHERE tabla_destino = 'metas_operativas' AND estado = 'EXITOSO'
    );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('metas_operativas', 'gs://ali1_bucket/raw/metas_operativas/', CAST(NULL AS DATE), 'INCREMENTAL', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- ============================================================
-- SECCIÓN 3: MAESTROS (snapshot completo en cada ejecución)
-- CTAS sobreescribe la tabla e inyecta fecha_snapshot en un paso
-- ============================================================

-- === CLIENTES ===
BEGIN
  CREATE OR REPLACE TABLE `sing1261.ali1_raw.clientes` AS
  SELECT *, CURRENT_TIMESTAMP() AS fecha_snapshot
  FROM `sing1261.ali1_raw.ext_clientes`;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES (
    'clientes', 'gs://ali1_bucket/raw/clientes/clientes_alicorp.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'EXITOSO', @@row_count, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('clientes', 'gs://ali1_bucket/raw/clientes/clientes_alicorp.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === PRODUCTOS ===
BEGIN
  CREATE OR REPLACE TABLE `sing1261.ali1_raw.productos` AS
  SELECT *, CURRENT_TIMESTAMP() AS fecha_snapshot
  FROM `sing1261.ali1_raw.ext_productos`;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES (
    'productos', 'gs://ali1_bucket/raw/productos/productos_alicorp.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'EXITOSO', @@row_count, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('productos', 'gs://ali1_bucket/raw/productos/productos_alicorp.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === CANAL ===
BEGIN
  CREATE OR REPLACE TABLE `sing1261.ali1_raw.canal` AS
  SELECT *, CURRENT_TIMESTAMP() AS fecha_snapshot
  FROM `sing1261.ali1_raw.ext_canal`;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES (
    'canal', 'gs://ali1_bucket/raw/canal/canal.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'EXITOSO', @@row_count, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('canal', 'gs://ali1_bucket/raw/canal/canal.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === GEOGRAFIA ===
BEGIN
  CREATE OR REPLACE TABLE `sing1261.ali1_raw.geografia` AS
  SELECT *, CURRENT_TIMESTAMP() AS fecha_snapshot
  FROM `sing1261.ali1_raw.ext_geografia`;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES (
    'geografia', 'gs://ali1_bucket/raw/geografia/geografia.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'EXITOSO', @@row_count, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('geografia', 'gs://ali1_bucket/raw/geografia/geografia.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === ALMACEN ===
BEGIN
  CREATE OR REPLACE TABLE `sing1261.ali1_raw.almacen` AS
  SELECT *, CURRENT_TIMESTAMP() AS fecha_snapshot
  FROM `sing1261.ali1_raw.ext_almacen`;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES (
    'almacen', 'gs://ali1_bucket/raw/almacen/almacen.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'EXITOSO', @@row_count, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('almacen', 'gs://ali1_bucket/raw/almacen/almacen.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- === VENDEDOR ===
BEGIN
  CREATE OR REPLACE TABLE `sing1261.ali1_raw.vendedor` AS
  SELECT *, CURRENT_TIMESTAMP() AS fecha_snapshot
  FROM `sing1261.ali1_raw.ext_vendedor`;

  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES (
    'vendedor', 'gs://ali1_bucket/raw/vendedor/vendedor.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'EXITOSO', @@row_count, CAST(NULL AS STRING), CURRENT_TIMESTAMP()
  );

EXCEPTION WHEN ERROR THEN
  INSERT INTO `sing1261.ali1_raw.etl_control`
    (tabla_destino, archivo_origen, fecha_particion, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
  VALUES ('vendedor', 'gs://ali1_bucket/raw/vendedor/vendedor.csv',
    CAST(NULL AS DATE), 'SNAPSHOT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
END;


-- ============================================================
-- SECCIÓN 4: LIMPIEZA — elimina las tablas externas temporales
-- ============================================================
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_ventas`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_pedidos`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_devoluciones`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_fill_rate`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_inventario`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_metas`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_promociones`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_inversion_promocional`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_metas_operativas`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_clientes`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_productos`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_canal`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_geografia`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_almacen`;
DROP TABLE IF EXISTS `sing1261.ali1_raw.ext_vendedor`;

END;
