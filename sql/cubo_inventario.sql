-- CUBO_INVENTARIO
-- Dataset: sing1261.ali1_kpi
-- Descripcion: Agrega metricas de inventario por fecha (snapshot mensual), almacen y producto.
-- KPIs cubiertos: Stock disponible, SKUs en quiebre, Tasa de quiebre %, Dias de cobertura,
--                 y sus respectivas metas operativas.

CREATE OR REPLACE VIEW `sing1261.ali1_kpi.CUBO_INVENTARIO` AS
SELECT
  t.anio, t.mes, t.mes_nombre, t.anio_mes, t.semana_anio, t.semana_label,
  t.fecha, t.periodo,
  a.nombre_almacen, a.tipo_almacen, a.macroregion, a.region, a.ciudad,
  p.linea_negocio, p.categoria, p.subcategoria, p.marca, p.cod_sku, p.nombre_sku,

  -- Metricas de inventario
  SUM(i.stock_disponible)                                                              AS stock_disponible,
  SUM(i.stock_reservado)                                                               AS stock_reservado,
  SUM(CASE WHEN i.stock_disponible <= 0 THEN 1 ELSE 0 END)                            AS skus_en_quiebre,
  COUNT(*)                                                                             AS total_skus,
  ROUND(SUM(CASE WHEN i.stock_disponible <= 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS tasa_quiebre_pct,
  ROUND(SUM(i.stock_disponible) / NULLIF(SUM(i.demanda_diaria_prom), 0), 1)           AS dias_cobertura,

  -- Metas operativas (granularidad almacen + mes)
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


-- KPIs derivados en el dashboard:
--
-- Tasa quiebre %     = SUM(skus_en_quiebre) / SUM(total_skus) * 100
-- Dias cobertura     = ya calculado en la vista (stock / demanda)
-- % vs meta quiebre  = tasa_quiebre_pct / meta_quiebre_pct * 100
