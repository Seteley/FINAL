-- CUBO_FACTURAS_MV
-- Materialized View para ticket promedio.
-- NOTA: BigQuery NO soporta COUNT(DISTINCT) en Materialized Views.
-- num_clientes_activos se elimina de aquí — se obtiene via get_frecuencia_compra()
-- que ya consulta FACT_VENTAS directamente con los filtros activos.
-- COUNT(*) es correcto porque fact_dedup ya tiene una fila por factura.

CREATE OR REPLACE MATERIALIZED VIEW `sing1261.ali1_kpi.CUBO_FACTURAS_MV`
OPTIONS (enable_refresh = true, refresh_interval_minutes = 60)
AS
WITH fact_dedup AS (
  -- Una fila por factura (elimina el multi-SKU antes de agregar)
  SELECT
    num_factura,
    id_fecha,
    id_canal,
    id_geografia,
    id_vendedor,
    SUM(ventas_netas_soles) AS ventas_netas_soles
  FROM `sing1261.ali1_curated.FACT_VENTAS`
  GROUP BY num_factura, id_fecha, id_canal, id_geografia, id_vendedor
)
SELECT
  t.anio, t.semestre, t.trimestre, t.mes, t.mes_nombre,
  t.anio_mes, t.semana_anio, t.semana_label, t.fecha, t.periodo,
  c.nombre_canal, c.tipo_canal,
  g.macroregion, g.Departamento, g.provincia, g.ciudad, g.tipo_zona,
  ve.nombre_completo AS nombre_vendedor, ve.zona_asignada,

  SUM(f.ventas_netas_soles) AS ventas_netas,
  COUNT(*)                  AS num_facturas

FROM fact_dedup f
JOIN `sing1261.ali1_curated.DIM_TIEMPO`    t  ON f.id_fecha     = t.id_fecha
JOIN `sing1261.ali1_curated.DIM_CANAL`     c  ON f.id_canal     = c.id_canal
JOIN `sing1261.ali1_curated.DIM_GEOGRAFIA` g  ON f.id_geografia = g.id_geografia
JOIN `sing1261.ali1_curated.DIM_VENDEDOR`  ve ON f.id_vendedor  = ve.id_vendedor
GROUP BY
  t.anio, t.semestre, t.trimestre, t.mes, t.mes_nombre,
  t.anio_mes, t.semana_anio, t.semana_label, t.fecha, t.periodo,
  c.nombre_canal, c.tipo_canal,
  g.macroregion, g.Departamento, g.provincia, g.ciudad, g.tipo_zona,
  ve.nombre_completo, ve.zona_asignada;
