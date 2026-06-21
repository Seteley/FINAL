-- =============================================================================
-- EVIDENCIA ELT — CAPA RAW
-- Dataset: sing1261.ali1_raw
-- Ejecutar después de: CALL `sing1261.ali1_raw.sp_etl_raw`()
-- =============================================================================


-- -----------------------------------------------------------------------------
-- E-RAW-01: Estado del ETL — todas las tablas cargaron sin error
-- Esperado: 0 filas con estado = 'ERROR'
-- -----------------------------------------------------------------------------
SELECT
  tabla_destino,
  tipo,
  estado,
  registros_cargados,
  mensaje_error,
  fecha_carga
FROM `sing1261.ali1_raw.etl_control`
WHERE estado = 'ERROR'
ORDER BY fecha_carga DESC;


-- -----------------------------------------------------------------------------
-- E-RAW-02: Resumen de carga — conteo de registros por tabla
-- Esperado: 15 tablas con estado EXITOSO y registros_cargados > 0
-- -----------------------------------------------------------------------------
SELECT
  tabla_destino,
  tipo,
  estado,
  registros_cargados,
  fecha_carga
FROM `sing1261.ali1_raw.etl_control`
WHERE estado = 'EXITOSO'
ORDER BY tabla_destino, fecha_carga DESC;


-- -----------------------------------------------------------------------------
-- E-RAW-03: Conteo real de filas en tablas transaccionales
-- Esperado: cada tabla con filas > 0
-- -----------------------------------------------------------------------------
SELECT 'ventas'               AS tabla, COUNT(*) AS filas FROM `sing1261.ali1_raw.ventas`               UNION ALL
SELECT 'pedidos',                        COUNT(*) FROM `sing1261.ali1_raw.pedidos`                        UNION ALL
SELECT 'devoluciones',                   COUNT(*) FROM `sing1261.ali1_raw.devoluciones`                   UNION ALL
SELECT 'fill_rate',                      COUNT(*) FROM `sing1261.ali1_raw.fill_rate`                      UNION ALL
SELECT 'inventario',                     COUNT(*) FROM `sing1261.ali1_raw.inventario`                     UNION ALL
SELECT 'metas',                          COUNT(*) FROM `sing1261.ali1_raw.metas`                          UNION ALL
SELECT 'metas_operativas',               COUNT(*) FROM `sing1261.ali1_raw.metas_operativas`               UNION ALL
SELECT 'promociones',                    COUNT(*) FROM `sing1261.ali1_raw.promociones`                    UNION ALL
SELECT 'inversion_promocional',          COUNT(*) FROM `sing1261.ali1_raw.inversion_promocional`
ORDER BY tabla;


-- -----------------------------------------------------------------------------
-- E-RAW-04: Conteo real de filas en tablas maestras (snapshot)
-- Esperado: cada tabla con filas > 0
-- -----------------------------------------------------------------------------
SELECT 'clientes'   AS tabla, COUNT(*) AS filas FROM `sing1261.ali1_raw.clientes`   UNION ALL
SELECT 'productos',             COUNT(*) FROM `sing1261.ali1_raw.productos`             UNION ALL
SELECT 'canal',                 COUNT(*) FROM `sing1261.ali1_raw.canal`                 UNION ALL
SELECT 'geografia',             COUNT(*) FROM `sing1261.ali1_raw.geografia`             UNION ALL
SELECT 'almacen',               COUNT(*) FROM `sing1261.ali1_raw.almacen`               UNION ALL
SELECT 'vendedor',              COUNT(*) FROM `sing1261.ali1_raw.vendedor`
ORDER BY tabla;


-- -----------------------------------------------------------------------------
-- E-RAW-05: Particiones cargadas en ventas
-- Esperado: múltiples fechas de partición con estado EXITOSO (carga incremental)
-- -----------------------------------------------------------------------------
SELECT
  tabla_destino,
  fecha_particion,
  estado,
  registros_cargados
FROM `sing1261.ali1_raw.etl_control`
WHERE tabla_destino = 'ventas'
  AND estado = 'EXITOSO'
ORDER BY fecha_particion;


-- -----------------------------------------------------------------------------
-- E-RAW-06: Ventas raw — verificar presencia de duplicados marcados por SAP
-- Esperado: existen registros con estado_linea = 'DUPLICADO' (son los que
--           trusted debe filtrar). Si el resultado es 0, el origen no los envió.
-- -----------------------------------------------------------------------------
SELECT
  estado_linea,
  COUNT(*) AS registros
FROM `sing1261.ali1_raw.ventas`
GROUP BY estado_linea
ORDER BY estado_linea;


-- -----------------------------------------------------------------------------
-- E-RAW-07: Inventario raw — stock negativo presente en origen
-- Esperado: registros con stock_disponible < 0 (evidencia del problema de calidad
--           VQ-02 que trusted corregirá con el filtro stock >= 0)
-- -----------------------------------------------------------------------------
SELECT
  COUNT(*)                                          AS total_registros,
  COUNTIF(stock_disponible < 0)                    AS con_stock_negativo,
  ROUND(COUNTIF(stock_disponible < 0) / COUNT(*) * 100, 2) AS pct_negativo
FROM `sing1261.ali1_raw.inventario`;


-- -----------------------------------------------------------------------------
-- E-RAW-08: Rango de fechas cargadas por tabla transaccional
-- Esperado: fechas entre 2023 y 2025 en todas las tablas
-- -----------------------------------------------------------------------------
SELECT 'ventas'    AS tabla, MIN(fecha_emision)    AS fecha_min, MAX(fecha_emision)    AS fecha_max FROM `sing1261.ali1_raw.ventas`    UNION ALL
SELECT 'pedidos',             MIN(fecha_pedido),                  MAX(fecha_pedido)                  FROM `sing1261.ali1_raw.pedidos`    UNION ALL
SELECT 'fill_rate',           MIN(fecha_despacho),                MAX(fecha_despacho)                FROM `sing1261.ali1_raw.fill_rate`  UNION ALL
SELECT 'inventario',          MIN(fecha_snapshot),                MAX(fecha_snapshot)                FROM `sing1261.ali1_raw.inventario`
ORDER BY tabla;


-- -----------------------------------------------------------------------------
-- E-RAW-09: Fill rate raw — nulos en transportista y motivo_rechazo
-- Esperado: porcentaje de nulos que trusted imputará con 'No especificado'
-- -----------------------------------------------------------------------------
SELECT
  COUNT(*)                                                  AS total,
  COUNTIF(transportista IS NULL)                           AS nulos_transportista,
  COUNTIF(motivo_rechazo IS NULL)                          AS nulos_motivo_rechazo,
  ROUND(COUNTIF(transportista IS NULL)  / COUNT(*) * 100, 1) AS pct_nulo_transportista,
  ROUND(COUNTIF(motivo_rechazo IS NULL) / COUNT(*) * 100, 1) AS pct_nulo_motivo
FROM `sing1261.ali1_raw.fill_rate`;


-- -----------------------------------------------------------------------------
-- E-RAW-10: Metas — versiones en origen (aprobadas vs no aprobadas)
-- Esperado: existen registros con es_version_aprobada = 0 que trusted descartará
-- -----------------------------------------------------------------------------
SELECT
  es_version_aprobada,
  COUNT(*) AS registros
FROM `sing1261.ali1_raw.metas`
GROUP BY es_version_aprobada;
