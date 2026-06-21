-- =============================================================================
-- EVIDENCIA ELT — CAPA KPI
-- Dataset: sing1261.ali1_kpi
-- Ejecutar después de: CALL `sing1261.ali1_kpi.sp_etl_kpi`()
-- =============================================================================


-- -----------------------------------------------------------------------------
-- E-KPI-01: Estado del ETL — 3 cubos creados sin error
-- Esperado: 0 filas con estado = 'ERROR'
-- -----------------------------------------------------------------------------
SELECT
  tabla_destino,
  tipo,
  estado,
  registros_cargados,
  mensaje_error,
  fecha_carga
FROM `sing1261.ali1_kpi.etl_control`
WHERE estado = 'ERROR'
ORDER BY fecha_carga DESC;


-- -----------------------------------------------------------------------------
-- E-KPI-02: Resumen de carga — 3 cubos con registros > 0
-- -----------------------------------------------------------------------------
SELECT
  tabla_destino,
  estado,
  registros_cargados,
  fecha_carga
FROM `sing1261.ali1_kpi.etl_control`
WHERE estado = 'EXITOSO'
ORDER BY tabla_destino;


-- -----------------------------------------------------------------------------
-- E-KPI-03: Conteo de filas en los 3 cubos
-- Esperado: todos con filas > 0
-- -----------------------------------------------------------------------------
SELECT 'CUBO_COMERCIAL_TBL'  AS cubo, COUNT(*) AS filas FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`  UNION ALL
SELECT 'CUBO_FACTURAS_TBL',           COUNT(*) FROM `sing1261.ali1_kpi.CUBO_FACTURAS_TBL`             UNION ALL
SELECT 'CUBO_INVENTARIO_TBL',         COUNT(*) FROM `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`
ORDER BY cubo;


-- -----------------------------------------------------------------------------
-- E-KPI-04: CUBO_COMERCIAL — consistencia de ventas vs FACT_VENTAS
-- Esperado: suma de ventas_netas en KPI = suma en FACT_VENTAS
-- -----------------------------------------------------------------------------
SELECT
  (SELECT ROUND(SUM(ventas_netas), 2)       FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`)     AS kpi_ventas_netas,
  (SELECT ROUND(SUM(ventas_netas_soles), 2) FROM `sing1261.ali1_curated.FACT_VENTAS`)         AS curated_ventas_netas,
  ROUND(
    ABS(
      (SELECT SUM(ventas_netas)       FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`) -
      (SELECT SUM(ventas_netas_soles) FROM `sing1261.ali1_curated.FACT_VENTAS`)
    ), 2
  ) AS diferencia_absoluta;


-- -----------------------------------------------------------------------------
-- E-KPI-05: CUBO_COMERCIAL — margen bruto positivo en todos los registros
-- Esperado: margen = ventas_netas - costo_ventas; no debe haber inconsistencias
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(margen_bruto < 0)                                   AS filas_margen_negativo,
  COUNTIF(ABS(margen_bruto - (ventas_netas - costo_ventas)) > 0.01) AS filas_margen_inconsistente,
  ROUND(SUM(ventas_netas), 2)                                 AS total_ventas_netas,
  ROUND(SUM(costo_ventas), 2)                                 AS total_costo_ventas,
  ROUND(SUM(margen_bruto), 2)                                 AS total_margen_bruto,
  ROUND(SUM(margen_bruto) / NULLIF(SUM(ventas_netas), 0) * 100, 2) AS margen_pct_global
FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`;


-- -----------------------------------------------------------------------------
-- E-KPI-06: CUBO_COMERCIAL — ventas netas totales por canal
-- Sirve para comparar contra metas y detectar canales sin datos
-- -----------------------------------------------------------------------------
SELECT
  nombre_canal,
  tipo_canal,
  ROUND(SUM(ventas_netas), 2)     AS ventas_netas,
  ROUND(SUM(meta_ventas_netas), 2) AS meta_ventas_netas,
  ROUND(SUM(ventas_netas) / NULLIF(SUM(meta_ventas_netas), 0) * 100, 1) AS cumplimiento_pct
FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`
GROUP BY nombre_canal, tipo_canal
ORDER BY ventas_netas DESC;


-- -----------------------------------------------------------------------------
-- E-KPI-07: CUBO_COMERCIAL — ventas netas totales por año y trimestre
-- Verifica cobertura temporal completa del cubo
-- -----------------------------------------------------------------------------
SELECT
  anio,
  trimestre,
  ROUND(SUM(ventas_netas), 2)     AS ventas_netas,
  ROUND(SUM(margen_bruto), 2)     AS margen_bruto,
  ROUND(SUM(inversion_promo), 2)  AS inversion_promo
FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`
GROUP BY anio, trimestre
ORDER BY anio, trimestre;


-- -----------------------------------------------------------------------------
-- E-KPI-08: CUBO_FACTURAS — ticket promedio y clientes activos por canal
-- Esperado: ticket_promedio = ventas_netas / num_facturas > 0 en todos los canales
-- -----------------------------------------------------------------------------
SELECT
  nombre_canal,
  tipo_canal,
  SUM(num_facturas)                                               AS total_facturas,
  COUNT(DISTINCT nombre_canal)                                    AS canales,
  ROUND(SUM(ventas_netas) / NULLIF(SUM(num_facturas), 0), 2)    AS ticket_promedio,
  SUM(num_clientes_activos)                                       AS clientes_activos
FROM `sing1261.ali1_kpi.CUBO_FACTURAS_TBL`
GROUP BY nombre_canal, tipo_canal
ORDER BY total_facturas DESC;


-- -----------------------------------------------------------------------------
-- E-KPI-09: CUBO_FACTURAS — consistencia de ventas_netas vs CUBO_COMERCIAL
-- Esperado: ambos cubos suman lo mismo (vienen de la misma FACT_VENTAS)
-- -----------------------------------------------------------------------------
SELECT
  (SELECT ROUND(SUM(ventas_netas), 2) FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`) AS comercial_ventas,
  (SELECT ROUND(SUM(ventas_netas), 2) FROM `sing1261.ali1_kpi.CUBO_FACTURAS_TBL`)  AS facturas_ventas,
  ROUND(
    ABS(
      (SELECT SUM(ventas_netas) FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`) -
      (SELECT SUM(ventas_netas) FROM `sing1261.ali1_kpi.CUBO_FACTURAS_TBL`)
    ), 2
  ) AS diferencia_absoluta;


-- -----------------------------------------------------------------------------
-- E-KPI-10: CUBO_INVENTARIO — tasa de quiebre dentro de rango válido [0, 100]
-- Esperado: tasa_quiebre_pct entre 0 y 100 en todos los registros
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(tasa_quiebre_pct < 0 OR tasa_quiebre_pct > 100) AS filas_fuera_de_rango,
  ROUND(MIN(tasa_quiebre_pct), 2)                          AS quiebre_minimo,
  ROUND(MAX(tasa_quiebre_pct), 2)                          AS quiebre_maximo,
  ROUND(AVG(tasa_quiebre_pct), 2)                          AS quiebre_promedio,
  ROUND(AVG(dias_cobertura), 1)                            AS cobertura_promedio_dias
FROM `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`;


-- -----------------------------------------------------------------------------
-- E-KPI-11: CUBO_INVENTARIO — tasa de quiebre por almacén
-- Sirve para comparar contra la meta meta_quiebre_pct y detectar almacenes críticos
-- -----------------------------------------------------------------------------
SELECT
  nombre_almacen,
  macroregion,
  ROUND(AVG(tasa_quiebre_pct), 2)    AS quiebre_pct_promedio,
  MAX(meta_quiebre_pct)              AS meta_quiebre_pct,
  ROUND(AVG(dias_cobertura), 1)      AS dias_cobertura_promedio,
  MAX(meta_dias_cobertura)           AS meta_dias_cobertura
FROM `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`
GROUP BY nombre_almacen, macroregion
ORDER BY quiebre_pct_promedio DESC;


-- -----------------------------------------------------------------------------
-- E-KPI-12: CUBO_INVENTARIO — consistencia stock vs FACT_INVENTARIO
-- Esperado: suma de stock_disponible igual en ambas capas
-- -----------------------------------------------------------------------------
SELECT
  (SELECT ROUND(SUM(stock_disponible), 2) FROM `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`)  AS kpi_stock,
  (SELECT ROUND(SUM(stock_disponible), 2) FROM `sing1261.ali1_curated.FACT_INVENTARIO`)   AS curated_stock,
  ROUND(
    ABS(
      (SELECT SUM(stock_disponible) FROM `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`) -
      (SELECT SUM(stock_disponible) FROM `sing1261.ali1_curated.FACT_INVENTARIO`)
    ), 2
  ) AS diferencia_absoluta;


-- -----------------------------------------------------------------------------
-- E-KPI-13: CUBO_INVENTARIO — metas operativas enlazadas (fill rate y OTIF)
-- Esperado: meta_fill_rate_pct y meta_otif_pct presentes y en rango [0, 100]
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(meta_fill_rate_pct IS NULL)                      AS sin_meta_fill_rate,
  COUNTIF(meta_otif_pct IS NULL)                           AS sin_meta_otif,
  ROUND(MIN(meta_fill_rate_pct), 2)                        AS fill_rate_meta_min,
  ROUND(MAX(meta_fill_rate_pct), 2)                        AS fill_rate_meta_max,
  ROUND(MIN(meta_otif_pct), 2)                             AS otif_meta_min,
  ROUND(MAX(meta_otif_pct), 2)                             AS otif_meta_max
FROM `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`;
