-- =============================================================================
-- VALIDACIÓN DE CALIDAD DE DATOS — CAPA RAW (ali1_raw)
-- Proyecto: sing1261
-- Dataset:  ali1_raw
-- =============================================================================
-- Cada bloque es una consulta independiente ejecutada por run_validacion_raw.py
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- [V01] ventas_alicorp — Conteo total y distribución por estado_linea
-- Esperado: 503,998 filas | DUPLICADO = 3,998 | ACTIVO = 500,000
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V01_ventas_conteo_estado'                      AS validacion,
  COUNT(*)                                         AS total_filas,
  COUNTIF(estado_linea = 'DUPLICADO')              AS filas_duplicado,
  COUNTIF(estado_linea = 'ACTIVO')                 AS filas_activo,
  COUNTIF(estado_linea NOT IN ('ACTIVO','DUPLICADO')) AS filas_estado_invalido,
  ROUND(COUNTIF(estado_linea = 'DUPLICADO') / COUNT(*) * 100, 2) AS pct_duplicado
FROM `sing1261.ali1_raw.ventas`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V02] ventas_alicorp — Verificar patrón _DUP en id_linea_venta de duplicados
-- Esperado: 3,998 filas con estado_linea=DUPLICADO tienen sufijo _DUP
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V02_ventas_sufijo_dup'                          AS validacion,
  COUNTIF(estado_linea = 'DUPLICADO' AND ENDS_WITH(CAST(id_linea_venta AS STRING), '_DUP'))
                                                   AS duplicados_con_sufijo_dup,
  COUNTIF(estado_linea = 'DUPLICADO' AND NOT ENDS_WITH(CAST(id_linea_venta AS STRING), '_DUP'))
                                                   AS duplicados_sin_sufijo_dup,
  COUNTIF(estado_linea = 'ACTIVO' AND ENDS_WITH(CAST(id_linea_venta AS STRING), '_DUP'))
                                                   AS activos_con_sufijo_dup
FROM `sing1261.ali1_raw.ventas`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V03] ventas_alicorp — Consistencia financiera básica (precios y cantidades)
-- Esperado: sin filas con precio_unitario <= 0 o cantidad_vendida <= 0 en ACTIVO
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V03_ventas_consistencia_numerica'               AS validacion,
  COUNTIF(CAST(cantidad_vendida AS INT64) <= 0)    AS cant_vendida_cero_o_neg,
  COUNTIF(CAST(precio_unitario_soles AS FLOAT64) <= 0) AS precio_unitario_cero_o_neg,
  COUNTIF(CAST(precio_lista_soles AS FLOAT64) <= 0)    AS precio_lista_cero_o_neg,
  COUNTIF(CAST(ventas_netas_soles AS FLOAT64) < 0)     AS ventas_netas_negativas,
  COUNTIF(CAST(descuento_pct AS FLOAT64) < 0 OR CAST(descuento_pct AS FLOAT64) > 100)
                                                   AS descuento_pct_fuera_rango
FROM `sing1261.ali1_raw.ventas`
WHERE estado_linea = 'ACTIVO';

-- ─────────────────────────────────────────────────────────────────────────────
-- [V04] fill_rate_despachos — NULLs en transportista y motivo_rechazo
-- Esperado: transportista NULL ~8.1% del total
--           motivo_rechazo NULL ~8.0% de las filas con flag_in_full=0
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V04_fill_rate_nulls'                            AS validacion,
  COUNT(*)                                         AS total_filas,
  COUNTIF(transportista IS NULL)                   AS transportista_null,
  ROUND(COUNTIF(transportista IS NULL) / COUNT(*) * 100, 2) AS pct_transportista_null,
  COUNTIF(CAST(flag_in_full AS INT64) = 0)         AS total_rechazos,
  COUNTIF(CAST(flag_in_full AS INT64) = 0 AND motivo_rechazo IS NULL)
                                                   AS motivo_rechazo_null_en_rechazos,
  ROUND(
    COUNTIF(CAST(flag_in_full AS INT64) = 0 AND motivo_rechazo IS NULL)
    / NULLIF(COUNTIF(CAST(flag_in_full AS INT64) = 0), 0) * 100
  , 2)                                             AS pct_motivo_null_sobre_rechazos
FROM `sing1261.ali1_raw.fill_rate`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V05] fill_rate_despachos — Consistencia flags OTIF
-- Esperado: flag_otif = 1 sólo si flag_on_time=1 AND flag_in_full=1
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V05_fill_rate_flags_otif'                       AS validacion,
  COUNT(*)                                         AS total_filas,
  COUNTIF(CAST(flag_otif AS INT64) = 1)            AS otif_positivos,
  COUNTIF(CAST(flag_on_time AS INT64) = 1 AND CAST(flag_in_full AS INT64) = 1) AS on_time_and_in_full,
  COUNTIF(
    CAST(flag_otif AS INT64) = 1
    AND NOT (CAST(flag_on_time AS INT64) = 1 AND CAST(flag_in_full AS INT64) = 1)
  )                                                AS otif_inconsistente,
  ROUND(COUNTIF(CAST(flag_otif AS INT64) = 1) / COUNT(*) * 100, 2) AS pct_otif
FROM `sing1261.ali1_raw.fill_rate`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V06] inventario_alicorp — Stock disponible negativo
-- Esperado: 1,640 filas con stock_disponible < 0 (~3.9%)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V06_inventario_stock_negativo'                  AS validacion,
  COUNT(*)                                         AS total_filas,
  COUNTIF(CAST(stock_disponible AS INT64) < 0)     AS stock_negativo,
  COUNTIF(CAST(stock_disponible AS INT64) = 0)     AS stock_cero,
  COUNTIF(CAST(stock_disponible AS INT64) > 0)     AS stock_positivo,
  ROUND(COUNTIF(CAST(stock_disponible AS INT64) < 0) / COUNT(*) * 100, 2) AS pct_stock_negativo
FROM `sing1261.ali1_raw.inventario`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V07] inventario_alicorp — flag_ajuste_pendiente vs stock negativo
-- Esperado: filas con stock<0 deberían tener flag_ajuste_pendiente='S'
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V07_inventario_flag_ajuste'                     AS validacion,
  COUNTIF(CAST(stock_disponible AS INT64) < 0)     AS stock_negativo_total,
  COUNTIF(CAST(stock_disponible AS INT64) < 0 AND flag_ajuste_pendiente = 'S')
                                                   AS neg_con_flag_ajuste_s,
  COUNTIF(CAST(stock_disponible AS INT64) < 0 AND flag_ajuste_pendiente = 'N')
                                                   AS neg_con_flag_ajuste_n,
  COUNTIF(CAST(stock_disponible AS INT64) < 0 AND flag_ajuste_pendiente IS NULL)
                                                   AS neg_con_flag_ajuste_null
FROM `sing1261.ali1_raw.inventario`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V08] clientes_alicorp — NULLs en direccion_fiscal
-- Esperado: 27 clientes (9%) con direccion_fiscal = NULL
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V08_clientes_direccion_null'                    AS validacion,
  COUNT(*)                                         AS total_clientes,
  COUNTIF(direccion_fiscal IS NULL)                AS direccion_null,
  ROUND(COUNTIF(direccion_fiscal IS NULL) / COUNT(*) * 100, 2) AS pct_direccion_null,
  COUNTIF(distrito IS NULL)                        AS distrito_null,
  COUNTIF(telefono IS NULL)                        AS telefono_null,
  COUNTIF(email_contacto IS NULL)                  AS email_null
FROM `sing1261.ali1_raw.clientes`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V09] clientes_alicorp — Concentración de NULLs en cohortes pre-2022
-- Esperado: clientes pre-2022 con direccion_fiscal=NULL son la mayoría
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V09_clientes_direccion_null_por_cohorte'        AS validacion,
  CASE
    WHEN CAST(fecha_alta_sistema AS DATE) < '2022-01-01' THEN 'pre_2022'
    ELSE '2022_en_adelante'
  END                                              AS cohorte,
  COUNT(*)                                         AS total,
  COUNTIF(direccion_fiscal IS NULL)                AS direccion_null,
  ROUND(COUNTIF(direccion_fiscal IS NULL) / COUNT(*) * 100, 2) AS pct_null
FROM `sing1261.ali1_raw.clientes`
GROUP BY cohorte
ORDER BY cohorte;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V10] productos_alicorp — cod_sap con sufijo _DUP
-- Esperado: 2 productos con cod_sap terminado en _DUP
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V10_productos_cod_sap_dup'                      AS validacion,
  COUNT(*)                                         AS total_productos,
  COUNTIF(ENDS_WITH(CAST(cod_sap AS STRING), '_DUP')) AS cod_sap_con_dup,
  COUNTIF(NOT ENDS_WITH(CAST(cod_sap AS STRING), '_DUP')) AS cod_sap_limpio
FROM `sing1261.ali1_raw.productos`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V11] productos_alicorp — Detalle de SKUs con cod_sap duplicado
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V11_productos_dup_detalle'                      AS validacion,
  id_producto_raw,
  cod_sku,
  cod_sap,
  nombre_sku,
  estado_producto
FROM `sing1261.ali1_raw.productos`
WHERE ENDS_WITH(CAST(cod_sap AS STRING), '_DUP')
ORDER BY cod_sap;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V12] promociones_alicorp — NULLs y heterogeneidad en id_promocion_sap
-- Esperado: 23.5% NULL (~50 campañas) | 5.6% con formato distinto
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V12_promociones_id_sap_nulls'                   AS validacion,
  COUNT(*)                                         AS total_promociones,
  COUNTIF(id_promocion_sap IS NULL)                AS id_sap_null,
  ROUND(COUNTIF(id_promocion_sap IS NULL) / COUNT(*) * 100, 2) AS pct_id_sap_null,
  COUNTIF(id_promocion_sap IS NOT NULL)            AS id_sap_presente,
  COUNTIF(
    id_promocion_sap IS NOT NULL
    AND NOT REGEXP_CONTAINS(id_promocion_sap, r'^\d{8,10}$')
  )                                                AS id_sap_formato_no_estandar,
  ROUND(
    COUNTIF(id_promocion_sap IS NOT NULL AND NOT REGEXP_CONTAINS(id_promocion_sap, r'^\d{8,10}$'))
    / NULLIF(COUNT(*), 0) * 100
  , 2)                                             AS pct_formato_no_estandar
FROM `sing1261.ali1_raw.promociones`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V13] metas_comerciales_raw — Versiones y filas aprobadas
-- Esperado: 655 filas totales | 216 con es_version_aprobada=1
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V13_metas_versiones'                            AS validacion,
  COUNT(*)                                         AS total_filas,
  COUNTIF(CAST(es_version_aprobada AS INT64) = 1)  AS filas_aprobadas,
  COUNTIF(CAST(es_version_aprobada AS INT64) = 0)  AS filas_no_aprobadas,
  COUNT(DISTINCT version_meta)                     AS versiones_distintas
FROM `sing1261.ali1_raw.metas`;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V14] metas_comerciales_raw — Distribución por version_meta
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V14_metas_dist_version'                         AS validacion,
  version_meta,
  COUNT(*)                                         AS filas,
  COUNTIF(CAST(es_version_aprobada AS INT64) = 1)  AS aprobadas,
  COUNTIF(aprobado_por IS NULL)                    AS sin_aprobador,
  COUNTIF(fecha_aprobacion IS NULL)                AS sin_fecha_aprobacion
FROM `sing1261.ali1_raw.metas`
GROUP BY version_meta
ORDER BY version_meta;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V15] devoluciones_alicorp — Estado de devoluciones y NULLs en nota_credito
-- Esperado: num_nota_credito NULL cuando estado != APROBADA
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V15_devoluciones_nota_credito'                  AS validacion,
  COUNT(*)                                         AS total_filas,
  estado_devolucion,
  COUNT(*)                                         AS filas_estado,
  COUNTIF(num_nota_credito IS NULL)                AS nota_credito_null,
  COUNTIF(fecha_aprobacion_dev IS NULL)            AS fecha_aprobacion_null
FROM `sing1261.ali1_raw.devoluciones`
GROUP BY estado_devolucion
ORDER BY estado_devolucion;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V16] inversion_promocional — Cruce con promociones (orphan keys)
-- Esperado: id_promocion_tm debería existir en ext_promociones
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  'V16_inversion_orphan_keys'                      AS validacion,
  COUNT(*)                                         AS total_inversiones,
  COUNTIF(inv.id_promocion_tm IS NULL)             AS inv_sin_id_tm,
  COUNTIF(inv.id_promocion_sap IS NULL)            AS inv_sin_id_sap,
  COUNTIF(promo.id_promocion_tm IS NULL AND inv.id_promocion_tm IS NOT NULL)
                                                   AS id_tm_sin_match_en_promociones
FROM `sing1261.ali1_raw.inversion_promocional` inv
LEFT JOIN `sing1261.ali1_raw.promociones` promo
  ON inv.id_promocion_tm = promo.id_promocion_tm;

-- ─────────────────────────────────────────────────────────────────────────────
-- [V17] RESUMEN EJECUTIVO — Semáforo de todos los problemas conocidos
-- ─────────────────────────────────────────────────────────────────────────────
WITH
  ventas AS (
    SELECT
      COUNT(*) AS total,
      COUNTIF(estado_linea = 'DUPLICADO') AS duplicados
    FROM `sing1261.ali1_raw.ventas`
  ),
  fill AS (
    SELECT
      COUNT(*) AS total,
      COUNTIF(transportista IS NULL) AS transportista_null,
      COUNTIF(CAST(flag_in_full AS INT64) = 0 AND motivo_rechazo IS NULL) AS motivo_null
    FROM `sing1261.ali1_raw.fill_rate`
  ),
  inv AS (
    SELECT
      COUNT(*) AS total,
      COUNTIF(CAST(stock_disponible AS INT64) < 0) AS stock_neg
    FROM `sing1261.ali1_raw.inventario`
  ),
  cli AS (
    SELECT
      COUNT(*) AS total,
      COUNTIF(direccion_fiscal IS NULL) AS dir_null
    FROM `sing1261.ali1_raw.clientes`
  ),
  prod AS (
    SELECT
      COUNT(*) AS total,
      COUNTIF(ENDS_WITH(CAST(cod_sap AS STRING), '_DUP')) AS cod_dup
    FROM `sing1261.ali1_raw.productos`
  ),
  promo AS (
    SELECT
      COUNT(*) AS total,
      COUNTIF(id_promocion_sap IS NULL) AS sap_null
    FROM `sing1261.ali1_raw.promociones`
  ),
  metas AS (
    SELECT
      COUNT(*) AS total,
      COUNTIF(CAST(es_version_aprobada AS INT64) = 1) AS aprobadas
    FROM `sing1261.ali1_raw.metas`
  )
SELECT 'V17_RESUMEN' AS validacion, resultado.*
FROM (
  SELECT
    'ventas_alicorp'          AS dataset,
    v.total                   AS filas_raw,
    v.duplicados              AS filas_problema,
    ROUND(v.duplicados / v.total * 100, 2) AS pct_problema,
    'estado_linea = DUPLICADO' AS descripcion_problema,
    IF(v.duplicados = 3998, 'OK_ESPERADO', 'REVISAR') AS semaforo
  FROM ventas v
  UNION ALL
  SELECT
    'fill_rate_despachos',
    f.total,
    f.transportista_null,
    ROUND(f.transportista_null / f.total * 100, 2),
    'transportista IS NULL',
    IF(f.transportista_null / f.total BETWEEN 0.07 AND 0.09, 'OK_ESPERADO', 'REVISAR')
  FROM fill f
  UNION ALL
  SELECT
    'inventario_alicorp',
    i.total,
    i.stock_neg,
    ROUND(i.stock_neg / i.total * 100, 2),
    'stock_disponible < 0',
    IF(i.stock_neg = 1640, 'OK_ESPERADO', 'REVISAR')
  FROM inv i
  UNION ALL
  SELECT
    'clientes_alicorp',
    c.total,
    c.dir_null,
    ROUND(c.dir_null / c.total * 100, 2),
    'direccion_fiscal IS NULL',
    IF(c.dir_null = 27, 'OK_ESPERADO', 'REVISAR')
  FROM cli c
  UNION ALL
  SELECT
    'productos_alicorp',
    p.total,
    p.cod_dup,
    ROUND(p.cod_dup / p.total * 100, 2),
    'cod_sap con sufijo _DUP',
    IF(p.cod_dup = 2, 'OK_ESPERADO', 'REVISAR')
  FROM prod p
  UNION ALL
  SELECT
    'promociones_alicorp',
    pr.total,
    pr.sap_null,
    ROUND(pr.sap_null / pr.total * 100, 2),
    'id_promocion_sap IS NULL',
    IF(pr.sap_null / pr.total BETWEEN 0.22 AND 0.25, 'OK_ESPERADO', 'REVISAR')
  FROM promo pr
  UNION ALL
  SELECT
    'metas_comerciales_raw',
    m.total,
    m.total - m.aprobadas,
    ROUND((m.total - m.aprobadas) / m.total * 100, 2),
    'es_version_aprobada != 1 (borradores)',
    IF(m.aprobadas = 216 AND m.total = 655, 'OK_ESPERADO', 'REVISAR')
  FROM metas m
) resultado
ORDER BY pct_problema DESC;

