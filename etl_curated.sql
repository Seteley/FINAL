CREATE OR REPLACE PROCEDURE `sing1261.ali1_curated.sp_etl_curated`()
BEGIN

  -- Tabla de control para la capa curada
  CREATE TABLE IF NOT EXISTS `sing1261.ali1_curated.etl_control`
  (
    tabla_destino      STRING    NOT NULL,
    tipo               STRING    NOT NULL,
    estado             STRING    NOT NULL,
    registros_cargados INT64,
    mensaje_error      STRING,
    fecha_carga        TIMESTAMP NOT NULL
  );

  -- =========================================================
  -- 1. DIM_TIEMPO — generada con GENERATE_DATE_ARRAY + feriados Perú
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.DIM_TIEMPO` AS
    WITH fechas AS (
      SELECT fecha
      FROM UNNEST(GENERATE_DATE_ARRAY('2023-01-01', '2025-12-31')) AS fecha
    ),
    feriados AS (
      SELECT fecha, nombre FROM UNNEST([
        STRUCT(DATE '2023-01-01' AS fecha, 'Año Nuevo' AS nombre),
        STRUCT(DATE '2023-04-06', 'Jueves Santo'),
        STRUCT(DATE '2023-04-07', 'Viernes Santo'),
        STRUCT(DATE '2023-05-01', 'Día del Trabajo'),
        STRUCT(DATE '2023-06-29', 'San Pedro y San Pablo'),
        STRUCT(DATE '2023-07-28', 'Fiestas Patrias'),
        STRUCT(DATE '2023-07-29', 'Fiestas Patrias'),
        STRUCT(DATE '2023-08-30', 'Santa Rosa de Lima'),
        STRUCT(DATE '2023-10-08', 'Combate de Angamos'),
        STRUCT(DATE '2023-11-01', 'Todos los Santos'),
        STRUCT(DATE '2023-12-08', 'Inmaculada Concepción'),
        STRUCT(DATE '2023-12-25', 'Navidad'),
        STRUCT(DATE '2024-01-01', 'Año Nuevo'),
        STRUCT(DATE '2024-03-28', 'Jueves Santo'),
        STRUCT(DATE '2024-03-29', 'Viernes Santo'),
        STRUCT(DATE '2024-05-01', 'Día del Trabajo'),
        STRUCT(DATE '2024-06-29', 'San Pedro y San Pablo'),
        STRUCT(DATE '2024-07-28', 'Fiestas Patrias'),
        STRUCT(DATE '2024-07-29', 'Fiestas Patrias'),
        STRUCT(DATE '2024-08-30', 'Santa Rosa de Lima'),
        STRUCT(DATE '2024-10-08', 'Combate de Angamos'),
        STRUCT(DATE '2024-11-01', 'Todos los Santos'),
        STRUCT(DATE '2024-12-08', 'Inmaculada Concepción'),
        STRUCT(DATE '2024-12-25', 'Navidad'),
        STRUCT(DATE '2025-01-01', 'Año Nuevo'),
        STRUCT(DATE '2025-04-17', 'Jueves Santo'),
        STRUCT(DATE '2025-04-18', 'Viernes Santo'),
        STRUCT(DATE '2025-05-01', 'Día del Trabajo'),
        STRUCT(DATE '2025-06-29', 'San Pedro y San Pablo'),
        STRUCT(DATE '2025-07-28', 'Fiestas Patrias'),
        STRUCT(DATE '2025-07-29', 'Fiestas Patrias'),
        STRUCT(DATE '2025-08-30', 'Santa Rosa de Lima'),
        STRUCT(DATE '2025-10-08', 'Combate de Angamos'),
        STRUCT(DATE '2025-11-01', 'Todos los Santos'),
        STRUCT(DATE '2025-12-08', 'Inmaculada Concepción'),
        STRUCT(DATE '2025-12-25', 'Navidad')
      ])
    )
    SELECT
      CAST(FORMAT_DATE('%Y%m%d', f.fecha) AS INT64)                AS id_fecha,
      f.fecha,
      EXTRACT(YEAR FROM f.fecha)                                   AS anio,
      CONCAT('Q', CAST(CEIL(EXTRACT(MONTH FROM f.fecha)/3.0) AS INT64)) AS trimestre,
      EXTRACT(MONTH FROM f.fecha)                                  AS mes,
      CASE EXTRACT(MONTH FROM f.fecha)
        WHEN 1  THEN 'Enero'      WHEN 2  THEN 'Febrero'
        WHEN 3  THEN 'Marzo'      WHEN 4  THEN 'Abril'
        WHEN 5  THEN 'Mayo'       WHEN 6  THEN 'Junio'
        WHEN 7  THEN 'Julio'      WHEN 8  THEN 'Agosto'
        WHEN 9  THEN 'Septiembre' WHEN 10 THEN 'Octubre'
        WHEN 11 THEN 'Noviembre'  WHEN 12 THEN 'Diciembre'
      END                                                          AS mes_nombre,
      EXTRACT(WEEK FROM f.fecha)                                   AS semana_anio,
      EXTRACT(DAY FROM f.fecha)                                    AS dia_mes,
      EXTRACT(DAYOFWEEK FROM f.fecha)                              AS dia_semana,
      CASE EXTRACT(DAYOFWEEK FROM f.fecha)
        WHEN 1 THEN 'Domingo'   WHEN 2 THEN 'Lunes'
        WHEN 3 THEN 'Martes'    WHEN 4 THEN 'Miércoles'
        WHEN 5 THEN 'Jueves'    WHEN 6 THEN 'Viernes'
        WHEN 7 THEN 'Sábado'
      END                                                          AS nombre_dia,
      IF(EXTRACT(DAYOFWEEK FROM f.fecha) IN (1, 7), 1, 0)         AS es_fin_semana,
      IF(fer.fecha IS NOT NULL, 1, 0)                              AS es_feriado,
      fer.nombre                                                   AS nombre_feriado,
      CAST(FORMAT_DATE('%Y%m', f.fecha) AS INT64)                  AS periodo,
      FORMAT_DATE('%Y-%m', f.fecha)                                AS anio_mes,
      CAST(CEIL(EXTRACT(MONTH FROM f.fecha)/6.0) AS INT64)         AS semestre,
      CONCAT('S', LPAD(CAST(EXTRACT(WEEK FROM f.fecha) AS STRING), 2, '0'), '-',
             CAST(EXTRACT(YEAR FROM f.fecha) AS STRING))           AS semana_label,
      IF(EXTRACT(DAYOFWEEK FROM f.fecha) NOT IN (1, 7)
         AND fer.fecha IS NULL, 1, 0)                              AS es_dia_habil
    FROM fechas f
    LEFT JOIN feriados fer ON f.fecha = fer.fecha;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.DIM_TIEMPO`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_TIEMPO', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_TIEMPO', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 2. DIM_CANAL
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.DIM_CANAL` AS
    SELECT id_canal, cod_canal, nombre_canal, tipo_canal, margen_objetivo_pct
    FROM `sing1261.ali1_trusted.canal`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.DIM_CANAL`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_CANAL', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_CANAL', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 3. DIM_GEOGRAFIA
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.DIM_GEOGRAFIA` AS
    SELECT id_geografia, pais, macroregion, Departamento, provincia, ciudad,
           distrito, tipo_zona, codigo_ubigeo
    FROM `sing1261.ali1_trusted.geografia`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.DIM_GEOGRAFIA`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_GEOGRAFIA', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_GEOGRAFIA', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 4. DIM_ALMACEN
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.DIM_ALMACEN` AS
    SELECT id_almacen, cod_almacen, nombre_almacen, tipo_almacen,
           macroregion, region, provincia, ciudad, distrito, tipo_zona, estado
    FROM `sing1261.ali1_trusted.almacen`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.DIM_ALMACEN`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_ALMACEN', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_ALMACEN', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 5. DIM_VENDEDOR
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.DIM_VENDEDOR` AS
    SELECT id_vendedor, cod_vendedor, nombre_completo, cargo,
           zona_asignada, fecha_ingreso, estado
    FROM `sing1261.ali1_trusted.vendedor`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.DIM_VENDEDOR`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_VENDEDOR', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_VENDEDOR', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 6. DIM_CLIENTE — clave derivada + fecha_primer_compra desde ventas
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.DIM_CLIENTE` AS
    SELECT
      CAST(REGEXP_EXTRACT(c.id_cliente_raw, r'\d+$') AS INT64) AS id_cliente,
      c.id_cliente_raw                                          AS cod_cliente,
      c.razon_social,
      c.ruc,
      c.tipo_persona                                            AS tipo_cliente,
      c.segmento_comercial                                      AS segmento,
      c.limite_credito_soles                                    AS credito_limite_soles,
      c.dias_credito,
      MIN(v.fecha_emision)                                      AS fecha_primer_compra
    FROM `sing1261.ali1_trusted.clientes` c
    LEFT JOIN `sing1261.ali1_trusted.ventas` v
      ON CAST(REGEXP_EXTRACT(c.id_cliente_raw, r'\d+$') AS INT64) = v.id_cliente
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.DIM_CLIENTE`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_CLIENTE', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_CLIENTE', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 7. DIM_PRODUCTO — clave derivada desde id_producto_raw
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.DIM_PRODUCTO` AS
    SELECT
      CAST(REGEXP_EXTRACT(id_producto_raw, r'\d+$') AS INT64) AS id_producto,
      cod_sku,
      nombre_sku,
      marca,
      categoria,
      subcategoria,
      linea_negocio,
      unidad_medida,
      contenido_neto,
      precio_lista_soles,
      costo_estandar_soles,
      estado_producto                                          AS estado
    FROM `sing1261.ali1_trusted.productos`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.DIM_PRODUCTO`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_PRODUCTO', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('DIM_PRODUCTO', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 8. FACT_VENTAS — join con devoluciones para imputar devueltos
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.FACT_VENTAS` AS
    SELECT
      ROW_NUMBER() OVER (ORDER BY v.fecha_emision, v.id_linea_venta)  AS id_venta,
      v.num_factura,
      CAST(FORMAT_DATE('%Y%m%d', v.fecha_emision) AS INT64)           AS id_fecha,
      v.id_cliente,
      v.id_producto,
      v.id_canal,
      v.id_geografia,
      v.id_vendedor,
      v.id_almacen,
      v.cantidad_vendida,
      v.precio_unitario_soles,
      v.monto_bruto_soles,
      v.descuento_pct,
      v.ventas_netas_soles,
      v.costo_ventas_soles,
      COALESCE(d.unidades_devueltas, 0)                               AS unidades_devueltas,
      COALESCE(d.monto_devuelto_soles, 0)                             AS monto_devuelto_soles,
      v.inversion_promocional_soles
    FROM `sing1261.ali1_trusted.ventas` v
    LEFT JOIN (
      SELECT
        num_factura_origen,
        id_producto,
        SUM(cantidad_devuelta)      AS unidades_devueltas,
        SUM(monto_devolucion_soles) AS monto_devuelto_soles
      FROM `sing1261.ali1_trusted.devoluciones`
      GROUP BY 1, 2
    ) d ON v.num_factura = d.num_factura_origen
       AND v.id_producto = d.id_producto;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.FACT_VENTAS`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('FACT_VENTAS', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('FACT_VENTAS', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 9. FACT_INVENTARIO
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.FACT_INVENTARIO` AS
    SELECT
      ROW_NUMBER() OVER (ORDER BY fecha_snapshot, id_producto, id_almacen) AS id_inventario,
      CAST(FORMAT_DATE('%Y%m%d', fecha_snapshot) AS INT64)                  AS id_fecha,
      id_producto,
      id_almacen,
      stock_disponible,
      stock_reservado,
      demanda_diaria_prom,
      flag_quiebre_stock  AS flag_quiebre,
      dias_cobertura_calc AS dias_cobertura
    FROM `sing1261.ali1_trusted.inventario`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.FACT_INVENTARIO`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('FACT_INVENTARIO', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('FACT_INVENTARIO', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 10. FACT_METAS_COMERCIAL
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.FACT_METAS_COMERCIAL` AS
    SELECT
      CAST(REGEXP_EXTRACT(id_meta_raw, r'\d+$') AS INT64)       AS id_meta,
      periodo,
      CAST(FORMAT_DATE('%Y%m%d', DATE(anio, mes, 1)) AS INT64)  AS id_fecha,
      id_canal,
      meta_ventas_netas_soles,
      meta_margen_bruto_soles,
      meta_margen_bruto_pct,
      meta_cantidad_vendida,
      meta_ticket_promedio_soles,
      meta_frecuencia_compra,
      meta_roi_promocional_pct,
      meta_tasa_devolucion_pct
    FROM `sing1261.ali1_trusted.metas`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.FACT_METAS_COMERCIAL`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('FACT_METAS_COMERCIAL', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('FACT_METAS_COMERCIAL', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 11. FACT_METAS_OPERATIVO — desde trusted.metas_operativas (solo versiones aprobadas)
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_curated.FACT_METAS_OPERATIVO` AS
    SELECT
      ROW_NUMBER() OVER (ORDER BY periodo, id_almacen)           AS id_meta_op,
      periodo,
      CAST(FORMAT_DATE('%Y%m%d', DATE(anio, mes, 1)) AS INT64)  AS id_fecha,
      id_almacen,
      meta_quiebre_pct,
      meta_dias_cobertura,
      meta_otif_pct,
      meta_fill_rate_pct
    FROM `sing1261.ali1_trusted.metas_operativas`;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_curated.FACT_METAS_OPERATIVO`);

    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('FACT_METAS_OPERATIVO', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_curated.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('FACT_METAS_OPERATIVO', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

END;
