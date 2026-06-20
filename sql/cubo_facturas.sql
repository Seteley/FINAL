-- CUBO_FACTURAS
-- Dataset: sing1261.ali1_kpi
-- Descripcion: Agrega metricas a nivel de factura (sin dimension de SKU/producto).
--              Necesario para calcular correctamente Ticket Promedio y Frecuencia de Compra,
--              ya que una factura puede tener multiples SKUs y se contaria doble en CUBO_COMERCIAL.
-- KPIs cubiertos: Ticket promedio, Frecuencia de compra.
-- Nota: Frecuencia compra global requiere COUNT DISTINCT directo a FACT_VENTAS (ver abajo).

CREATE OR REPLACE VIEW `sing1261.ali1_kpi.CUBO_FACTURAS` AS
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


-- KPIs derivados en el dashboard:
--
-- Ticket promedio    = SUM(ventas_netas) / SUM(num_facturas)
--
-- Frecuencia compra global (query directa, no del cubo):
--   SELECT COUNT(DISTINCT num_factura) / COUNT(DISTINCT id_cliente)
--   FROM `sing1261.ali1_curated.FACT_VENTAS`
--   WHERE <filtros activos>
