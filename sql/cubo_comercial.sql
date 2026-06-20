-- CUBO_COMERCIAL
-- Dataset: sing1261.ali1_kpi
-- Descripcion: Agrega metricas comerciales por fecha, canal, geografia, producto y vendedor.
-- KPIs cubiertos: Ventas netas, Margen bruto, Margen %, Cantidad vendida,
--                 Tasa devolucion, ROI promocional, y sus respectivas metas.
-- Nota: Ticket promedio y Frecuencia compra NO se calculan aqui (usar CUBO_FACTURAS).

CREATE OR REPLACE VIEW `sing1261.ali1_kpi.CUBO_COMERCIAL` AS
SELECT
  t.anio, t.semestre, t.trimestre, t.mes, t.mes_nombre,
  t.anio_mes, t.semana_anio, t.semana_label, t.fecha, t.periodo,
  c.nombre_canal, c.tipo_canal,
  g.macroregion, g.Departamento, g.provincia, g.ciudad, g.tipo_zona,
  p.linea_negocio, p.categoria, p.subcategoria, p.marca, p.cod_sku, p.nombre_sku,
  ve.nombre_completo AS nombre_vendedor, ve.zona_asignada,

  -- Metricas de ventas
  SUM(v.ventas_netas_soles)                        AS ventas_netas,
  SUM(v.monto_bruto_soles)                         AS venta_bruta,
  SUM(v.costo_ventas_soles)                        AS costo_ventas,
  SUM(v.ventas_netas_soles - v.costo_ventas_soles) AS margen_bruto,
  SUM(v.inversion_promocional_soles)               AS inversion_promo,
  SUM(v.cantidad_vendida)                          AS cantidad_vendida,
  SUM(v.unidades_devueltas)                        AS unidades_devueltas,
  SUM(v.monto_devuelto_soles)                      AS monto_devuelto,

  -- Metas comerciales (granularidad canal + mes)
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


-- KPIs derivados en el dashboard (no en el cubo):
--
-- Margen %           = SUM(margen_bruto) / SUM(ventas_netas) * 100
-- ROI promocional %  = (SUM(margen_bruto) - SUM(inversion_promo)) / SUM(inversion_promo) * 100
-- Tasa devolucion %  = SUM(unidades_devueltas) / SUM(cantidad_vendida) * 100
-- % Cumplimiento     = SUM(ventas_netas) / SUM(meta_ventas_netas) * 100
