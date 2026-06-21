-- CUBO_INVENTARIO_MV
-- Materialized View para inventario.
-- NOTA: BigQuery NO soporta expresiones que combinen múltiples agregaciones
-- (ej. SUM(a)/SUM(b)) en Materialized Views.
-- tasa_quiebre_pct y dias_cobertura se eliminan del cubo y se derivan en el dashboard
-- usando skus_en_quiebre/total_skus y stock_disponible/demanda_diaria_total.

CREATE OR REPLACE MATERIALIZED VIEW `sing1261.ali1_kpi.CUBO_INVENTARIO_MV`
OPTIONS (enable_refresh = true, refresh_interval_minutes = 60)
AS
SELECT
  t.anio, t.mes, t.mes_nombre, t.anio_mes, t.semana_anio, t.semana_label,
  t.fecha, t.periodo,
  a.nombre_almacen, a.tipo_almacen, a.macroregion, a.region, a.ciudad,
  p.linea_negocio, p.categoria, p.subcategoria, p.marca, p.cod_sku, p.nombre_sku,

  SUM(i.stock_disponible)                                       AS stock_disponible,
  SUM(i.stock_reservado)                                        AS stock_reservado,
  SUM(CASE WHEN i.stock_disponible <= 0 THEN 1 ELSE 0 END)     AS skus_en_quiebre,
  COUNT(*)                                                      AS total_skus,
  SUM(i.demanda_diaria_prom)                                    AS demanda_diaria_total,

  -- Metas operativas
  MAX(mo.meta_quiebre_pct)      AS meta_quiebre_pct,
  MAX(mo.meta_dias_cobertura)   AS meta_dias_cobertura,
  MAX(mo.meta_otif_pct)         AS meta_otif_pct,
  MAX(mo.meta_fill_rate_pct)    AS meta_fill_rate_pct

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

-- KPIs derivados en el dashboard:
-- tasa_quiebre_pct  = skus_en_quiebre / total_skus * 100
-- dias_cobertura    = stock_disponible / NULLIF(demanda_diaria_total, 0)
