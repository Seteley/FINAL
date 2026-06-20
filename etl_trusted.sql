CREATE OR REPLACE PROCEDURE `sing1261.ali1_trusted.sp_etl_trusted`()
BEGIN

  -- Tabla de control para la capa trusted
  CREATE TABLE IF NOT EXISTS `sing1261.ali1_trusted.etl_control`
  (
    tabla_destino      STRING    NOT NULL,
    tipo               STRING    NOT NULL,
    estado             STRING    NOT NULL,
    registros_cargados INT64,
    mensaje_error      STRING,
    fecha_carga        TIMESTAMP NOT NULL
  );

  -- =========================================================
  -- 1. ventas: eliminar duplicados SAP y limpiar sufijo _DUP
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.ventas`
    PARTITION BY fecha_emision AS
    SELECT
      * EXCEPT(id_linea_venta, fecha_carga),
      REGEXP_REPLACE(id_linea_venta, r'_DUP$', '') AS id_linea_venta,
      fecha_carga AS fecha_carga_raw
    FROM `sing1261.ali1_raw.ventas`
    WHERE estado_linea <> 'DUPLICADO';

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.ventas`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('ventas', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('ventas', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 2. pedidos: pass-through
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.pedidos`
    PARTITION BY fecha_pedido AS
    SELECT
      * EXCEPT(fecha_carga),
      fecha_carga AS fecha_carga_raw
    FROM `sing1261.ali1_raw.pedidos`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.pedidos`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pedidos', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pedidos', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 3. fill_rate: imputar NULLs en transportista y motivo_rechazo
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.fill_rate`
    PARTITION BY fecha_despacho AS
    SELECT
      * EXCEPT(transportista, motivo_rechazo, fecha_carga),
      COALESCE(transportista, 'No especificado')  AS transportista,
      COALESCE(motivo_rechazo, 'No especificado') AS motivo_rechazo,
      fecha_carga AS fecha_carga_raw
    FROM `sing1261.ali1_raw.fill_rate`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.fill_rate`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('fill_rate', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('fill_rate', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 4. inventario: eliminar stock negativo no conciliado
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.inventario`
    PARTITION BY fecha_snapshot AS
    SELECT
      * EXCEPT(fecha_carga),
      fecha_carga AS fecha_carga_raw
    FROM `sing1261.ali1_raw.inventario`
    WHERE stock_disponible >= 0;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.inventario`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('inventario', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('inventario', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 5. devoluciones: pass-through
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.devoluciones`
    PARTITION BY fecha_solicitud_dev AS
    SELECT
      * EXCEPT(fecha_carga),
      fecha_carga AS fecha_carga_raw
    FROM `sing1261.ali1_raw.devoluciones`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.devoluciones`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('devoluciones', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('devoluciones', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 6. metas: solo versiones aprobadas
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.metas` AS
    SELECT
      * EXCEPT(fecha_carga),
      fecha_carga AS fecha_carga_raw
    FROM `sing1261.ali1_raw.metas`
    WHERE es_version_aprobada = 1;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.metas`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('metas', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('metas', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 7. promociones: trim de id_promocion_sap + flag_sap_id_pendiente
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.promociones` AS
    SELECT
      * EXCEPT(id_promocion_sap, fecha_carga),
      TRIM(id_promocion_sap) AS id_promocion_sap,
      CASE
        WHEN id_promocion_sap IS NULL OR TRIM(id_promocion_sap) = '' THEN 1
        ELSE 0
      END AS flag_sap_id_pendiente,
      fecha_carga AS fecha_carga_raw
    FROM `sing1261.ali1_raw.promociones`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.promociones`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('promociones', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('promociones', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 8. inversion_promocional: pass-through
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.inversion_promocional` AS
    SELECT * FROM `sing1261.ali1_raw.inversion_promocional`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.inversion_promocional`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('inversion_promocional', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('inversion_promocional', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 9. clientes: agregar flag_direccion_completa
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.clientes` AS
    SELECT
      * EXCEPT(fecha_snapshot),
      CASE WHEN direccion_fiscal IS NULL THEN 0 ELSE 1 END AS flag_direccion_completa,
      fecha_snapshot
    FROM `sing1261.ali1_raw.clientes`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.clientes`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('clientes', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('clientes', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 10. productos: limpiar sufijo _DUP de cod_sap
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.productos` AS
    SELECT
      * EXCEPT(cod_sap, fecha_snapshot),
      REGEXP_REPLACE(cod_sap, r'_DUP$', '') AS cod_sap,
      fecha_snapshot
    FROM `sing1261.ali1_raw.productos`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.productos`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('productos', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('productos', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 11. metas_operativas: solo versiones aprobadas
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.metas_operativas` AS
    SELECT
      * EXCEPT(fecha_carga),
      fecha_carga AS fecha_carga_raw
    FROM `sing1261.ali1_raw.metas_operativas`
    WHERE es_version_aprobada = 1;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.metas_operativas`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('metas_operativas', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('metas_operativas', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 12. canal: pass-through (antes 11)
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.canal` AS
    SELECT * FROM `sing1261.ali1_raw.canal`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.canal`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('canal', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('canal', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 12. geografia: pass-through
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.geografia` AS
    SELECT * FROM `sing1261.ali1_raw.geografia`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.geografia`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('geografia', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('geografia', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 13. almacen: pass-through
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.almacen` AS
    SELECT * FROM `sing1261.ali1_raw.almacen`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.almacen`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('almacen', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('almacen', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 14. vendedor: pass-through
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_trusted.vendedor` AS
    SELECT * FROM `sing1261.ali1_raw.vendedor`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_trusted.vendedor`);

    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('vendedor', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_trusted.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('vendedor', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

END;
