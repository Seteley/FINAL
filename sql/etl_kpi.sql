CREATE OR REPLACE PROCEDURE `sing1261.ali1_kpi.sp_etl_kpi`()
BEGIN

  -- Tabla de control para la capa KPI
  CREATE TABLE IF NOT EXISTS `sing1261.ali1_kpi.etl_control`
  (
    tabla_destino      STRING    NOT NULL,
    tipo               STRING    NOT NULL,
    estado             STRING    NOT NULL,
    registros_cargados INT64,
    mensaje_error      STRING,
    fecha_carga        TIMESTAMP NOT NULL
  );

  -- =========================================================
  -- 1. CUBO_COMERCIAL_TBL
  --    Metricas de ventas, margen y metas comerciales.
  --    Granularidad: fecha x canal x geografia x producto x vendedor.
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL` AS
    SELECT
      t.anio, t.semestre, t.trimestre, t.mes, t.mes_nombre,
      t.anio_mes, t.semana_anio, t.semana_label, t.fecha, t.periodo,
      c.nombre_canal, c.tipo_canal,
      g.macroregion, g.Departamento, g.provincia, g.ciudad, g.tipo_zona,
      p.linea_negocio, p.categoria, p.subcategoria, p.marca, p.cod_sku, p.nombre_sku,
      ve.nombre_completo AS nombre_vendedor, ve.zona_asignada,

      SUM(v.ventas_netas_soles)                        AS ventas_netas,
      SUM(v.monto_bruto_soles)                         AS venta_bruta,
      SUM(v.costo_ventas_soles)                        AS costo_ventas,
      SUM(v.ventas_netas_soles - v.costo_ventas_soles) AS margen_bruto,
      SUM(v.inversion_promocional_soles)               AS inversion_promo,
      SUM(v.cantidad_vendida)                          AS cantidad_vendida,
      SUM(v.unidades_devueltas)                        AS unidades_devueltas,
      SUM(v.monto_devuelto_soles)                      AS monto_devuelto,

      MAX(m.meta_ventas_netas_soles)                   AS meta_ventas_netas,
      MAX(m.meta_margen_bruto_soles)                   AS meta_margen_bruto,
      MAX(m.meta_margen_bruto_pct)                     AS meta_margen_pct,
      MAX(m.meta_cantidad_vendida)                     AS meta_cantidad_vendida,
      MAX(m.meta_ticket_promedio_soles)                AS meta_ticket_promedio,
      MAX(m.meta_frecuencia_compra)                    AS meta_frecuencia_compra,
      MAX(m.meta_roi_promocional_pct)                  AS meta_roi_pct,
      MAX(m.meta_tasa_devolucion_pct)                  AS meta_tasa_devolucion

    FROM `sing1261.ali1_curated.FACT_VENTAS` v
    JOIN `sing1261.ali1_curated.DIM_TIEMPO`    t  ON v.id_fecha     = t.id_fecha
    JOIN `sing1261.ali1_curated.DIM_CANAL`     c  ON v.id_canal     = c.id_canal
    JOIN `sing1261.ali1_curated.DIM_GEOGRAFIA` g  ON v.id_geografia = g.id_geografia
    JOIN `sing1261.ali1_curated.DIM_PRODUCTO`  p  ON v.id_producto  = p.id_producto
    JOIN `sing1261.ali1_curated.DIM_VENDEDOR`  ve ON v.id_vendedor  = ve.id_vendedor
    JOIN `sing1261.ali1_curated.FACT_METAS_COMERCIAL` m
      ON t.periodo = m.periodo AND v.id_canal = m.id_canal
    GROUP BY
      t.anio, t.semestre, t.trimestre, t.mes, t.mes_nombre,
      t.anio_mes, t.semana_anio, t.semana_label, t.fecha, t.periodo,
      c.nombre_canal, c.tipo_canal,
      g.macroregion, g.Departamento, g.provincia, g.ciudad, g.tipo_zona,
      p.linea_negocio, p.categoria, p.subcategoria, p.marca, p.cod_sku, p.nombre_sku,
      ve.nombre_completo, ve.zona_asignada;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`);

    INSERT INTO `sing1261.ali1_kpi.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('CUBO_COMERCIAL_TBL', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_kpi.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('CUBO_COMERCIAL_TBL', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), @@error.message, CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 2. CUBO_FACTURAS_TBL
  --    Metricas a nivel de factura para Ticket Promedio y Frecuencia de Compra.
  --    Sin dimension Producto para evitar doble conteo por multi-SKU.
  --    COUNT DISTINCT es posible porque es tabla, no Materialized View.
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_kpi.CUBO_FACTURAS_TBL` AS
    SELECT
      t.anio, t.semestre, t.trimestre, t.mes, t.mes_nombre,
      t.anio_mes, t.semana_anio, t.semana_label, t.fecha, t.periodo,
      c.nombre_canal, c.tipo_canal,
      g.macroregion, g.Departamento, g.provincia, g.ciudad, g.tipo_zona,
      ve.nombre_completo AS nombre_vendedor, ve.zona_asignada,

      SUM(v.ventas_netas_soles)     AS ventas_netas,
      COUNT(DISTINCT v.num_factura) AS num_facturas,
      COUNT(DISTINCT v.id_cliente)  AS num_clientes_activos

    FROM `sing1261.ali1_curated.FACT_VENTAS` v
    JOIN `sing1261.ali1_curated.DIM_TIEMPO`    t  ON v.id_fecha     = t.id_fecha
    JOIN `sing1261.ali1_curated.DIM_CANAL`     c  ON v.id_canal     = c.id_canal
    JOIN `sing1261.ali1_curated.DIM_GEOGRAFIA` g  ON v.id_geografia = g.id_geografia
    JOIN `sing1261.ali1_curated.DIM_VENDEDOR`  ve ON v.id_vendedor  = ve.id_vendedor
    GROUP BY
      t.anio, t.semestre, t.trimestre, t.mes, t.mes_nombre,
      t.anio_mes, t.semana_anio, t.semana_label, t.fecha, t.periodo,
      c.nombre_canal, c.tipo_canal,
      g.macroregion, g.Departamento, g.provincia, g.ciudad, g.tipo_zona,
      ve.nombre_completo, ve.zona_asignada;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_kpi.CUBO_FACTURAS_TBL`);

    INSERT INTO `sing1261.ali1_kpi.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('CUBO_FACTURAS_TBL', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_kpi.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('CUBO_FACTURAS_TBL', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), @@error.message, CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- 3. CUBO_INVENTARIO_TBL
  --    Snapshot mensual de inventario por almacen y producto.
  --    tasa_quiebre_pct y dias_cobertura se calculan aqui (no en el dashboard).
  --    Division entre SUMs es posible porque es tabla, no Materialized View.
  -- =========================================================
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL` AS
    SELECT
      t.anio, t.mes, t.mes_nombre, t.anio_mes, t.semana_anio, t.semana_label,
      t.fecha, t.periodo,
      a.nombre_almacen, a.tipo_almacen, a.macroregion, a.region, a.ciudad,
      p.linea_negocio, p.categoria, p.subcategoria, p.marca, p.cod_sku, p.nombre_sku,

      SUM(i.stock_disponible)                                                              AS stock_disponible,
      SUM(i.stock_reservado)                                                               AS stock_reservado,
      SUM(CASE WHEN i.stock_disponible <= 0 THEN 1 ELSE 0 END)                            AS skus_en_quiebre,
      COUNT(*)                                                                             AS total_skus,
      ROUND(SUM(CASE WHEN i.stock_disponible <= 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS tasa_quiebre_pct,
      ROUND(SUM(i.stock_disponible) / NULLIF(SUM(i.demanda_diaria_prom), 0), 1)           AS dias_cobertura,

      MAX(mo.meta_quiebre_pct)                                                             AS meta_quiebre_pct,
      MAX(mo.meta_dias_cobertura)                                                          AS meta_dias_cobertura,
      MAX(mo.meta_otif_pct)                                                                AS meta_otif_pct,
      MAX(mo.meta_fill_rate_pct)                                                           AS meta_fill_rate_pct

    FROM `sing1261.ali1_curated.FACT_INVENTARIO` i
    JOIN `sing1261.ali1_curated.DIM_TIEMPO`   t  ON i.id_fecha    = t.id_fecha
    JOIN `sing1261.ali1_curated.DIM_ALMACEN`  a  ON i.id_almacen  = a.id_almacen
    JOIN `sing1261.ali1_curated.DIM_PRODUCTO` p  ON i.id_producto = p.id_producto
    JOIN `sing1261.ali1_curated.FACT_METAS_OPERATIVO` mo
      ON t.periodo = mo.periodo AND i.id_almacen = mo.id_almacen
    GROUP BY
      t.anio, t.mes, t.mes_nombre, t.anio_mes, t.semana_anio, t.semana_label,
      t.fecha, t.periodo,
      a.nombre_almacen, a.tipo_almacen, a.macroregion, a.region, a.ciudad,
      p.linea_negocio, p.categoria, p.subcategoria, p.marca, p.cod_sku, p.nombre_sku;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`);

    INSERT INTO `sing1261.ali1_kpi.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('CUBO_INVENTARIO_TBL', 'FULL_REFRESH', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_kpi.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('CUBO_INVENTARIO_TBL', 'FULL_REFRESH', 'ERROR', CAST(NULL AS INT64), @@error.message, CURRENT_TIMESTAMP());
  END;

END;
