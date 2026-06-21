-- =============================================================================
-- EVIDENCIA ELT — CAPA CURATED (modelo estrella)
-- Dataset: sing1261.ali1_curated
-- Ejecutar después de: CALL `sing1261.ali1_curated.sp_etl_curated`()
-- =============================================================================


-- -----------------------------------------------------------------------------
-- E-CUR-01: Estado del ETL — 11 objetos creados sin error
-- Esperado: 0 filas con estado = 'ERROR'
-- -----------------------------------------------------------------------------
SELECT
  tabla_destino,
  tipo,
  estado,
  registros_cargados,
  mensaje_error,
  fecha_carga
FROM `sing1261.ali1_curated.etl_control`
WHERE estado = 'ERROR'
ORDER BY fecha_carga DESC;


-- -----------------------------------------------------------------------------
-- E-CUR-02: Resumen de carga — 11 tablas (7 dims + 4 hechos) con filas > 0
-- -----------------------------------------------------------------------------
SELECT
  tabla_destino,
  estado,
  registros_cargados,
  fecha_carga
FROM `sing1261.ali1_curated.etl_control`
WHERE estado = 'EXITOSO'
ORDER BY tabla_destino;


-- -----------------------------------------------------------------------------
-- E-CUR-03: DIM_TIEMPO — cobertura de fechas esperada 2023-01-01 a 2025-12-31
-- Esperado: 1096 días, sin huecos, feriados Perú presentes
-- -----------------------------------------------------------------------------
SELECT
  COUNT(*)                                AS total_dias,
  MIN(fecha)                              AS fecha_minima,
  MAX(fecha)                              AS fecha_maxima,
  COUNTIF(es_feriado = 1)                AS dias_feriado,
  COUNTIF(es_dia_habil = 1)              AS dias_habiles,
  COUNTIF(es_fin_semana = 1)             AS dias_fin_semana,
  COUNT(DISTINCT anio)                   AS anios_distintos,
  COUNT(DISTINCT trimestre)              AS trimestres_distintos
FROM `sing1261.ali1_curated.DIM_TIEMPO`;


-- -----------------------------------------------------------------------------
-- E-CUR-04: DIM_TIEMPO — unicidad de id_fecha (PK = YYYYMMDD)
-- Esperado: 0 duplicados
-- -----------------------------------------------------------------------------
SELECT
  id_fecha,
  COUNT(*) AS veces
FROM `sing1261.ali1_curated.DIM_TIEMPO`
GROUP BY id_fecha
HAVING COUNT(*) > 1;


-- -----------------------------------------------------------------------------
-- E-CUR-05: Dimensiones — conteo de registros en cada dimensión
-- -----------------------------------------------------------------------------
SELECT 'DIM_TIEMPO'     AS dimension, COUNT(*) AS filas FROM `sing1261.ali1_curated.DIM_TIEMPO`     UNION ALL
SELECT 'DIM_CANAL',                   COUNT(*) FROM `sing1261.ali1_curated.DIM_CANAL`               UNION ALL
SELECT 'DIM_GEOGRAFIA',               COUNT(*) FROM `sing1261.ali1_curated.DIM_GEOGRAFIA`           UNION ALL
SELECT 'DIM_ALMACEN',                 COUNT(*) FROM `sing1261.ali1_curated.DIM_ALMACEN`             UNION ALL
SELECT 'DIM_VENDEDOR',                COUNT(*) FROM `sing1261.ali1_curated.DIM_VENDEDOR`            UNION ALL
SELECT 'DIM_CLIENTE',                 COUNT(*) FROM `sing1261.ali1_curated.DIM_CLIENTE`             UNION ALL
SELECT 'DIM_PRODUCTO',                COUNT(*) FROM `sing1261.ali1_curated.DIM_PRODUCTO`
ORDER BY dimension;


-- -----------------------------------------------------------------------------
-- E-CUR-06: Tablas de hechos — conteo de registros
-- -----------------------------------------------------------------------------
SELECT 'FACT_VENTAS'           AS hecho, COUNT(*) AS filas FROM `sing1261.ali1_curated.FACT_VENTAS`           UNION ALL
SELECT 'FACT_INVENTARIO',                COUNT(*) FROM `sing1261.ali1_curated.FACT_INVENTARIO`                UNION ALL
SELECT 'FACT_METAS_COMERCIAL',           COUNT(*) FROM `sing1261.ali1_curated.FACT_METAS_COMERCIAL`           UNION ALL
SELECT 'FACT_METAS_OPERATIVO',           COUNT(*) FROM `sing1261.ali1_curated.FACT_METAS_OPERATIVO`
ORDER BY hecho;


-- -----------------------------------------------------------------------------
-- E-CUR-07: FACT_VENTAS — consistencia con trusted.ventas
-- Esperado: mismo número de filas (curated no filtra, solo enriquece)
-- -----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `sing1261.ali1_trusted.ventas`)   AS trusted_ventas,
  (SELECT COUNT(*) FROM `sing1261.ali1_curated.FACT_VENTAS`) AS curated_fact_ventas,
  (SELECT COUNT(*) FROM `sing1261.ali1_trusted.ventas`) -
  (SELECT COUNT(*) FROM `sing1261.ali1_curated.FACT_VENTAS`) AS diferencia;


-- -----------------------------------------------------------------------------
-- E-CUR-08: FACT_VENTAS — integridad referencial hacia todas las dimensiones
-- Esperado: 0 claves foráneas sin correspondencia en la dimensión
-- -----------------------------------------------------------------------------
SELECT 'sin_dim_tiempo'    AS check_nombre, COUNT(*) AS huerfanos FROM `sing1261.ali1_curated.FACT_VENTAS` v WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_TIEMPO`    d WHERE d.id_fecha     = v.id_fecha)     UNION ALL
SELECT 'sin_dim_canal',                    COUNT(*) FROM `sing1261.ali1_curated.FACT_VENTAS` v WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_CANAL`     d WHERE d.id_canal     = v.id_canal)     UNION ALL
SELECT 'sin_dim_producto',                 COUNT(*) FROM `sing1261.ali1_curated.FACT_VENTAS` v WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_PRODUCTO`  d WHERE d.id_producto  = v.id_producto)  UNION ALL
SELECT 'sin_dim_cliente',                  COUNT(*) FROM `sing1261.ali1_curated.FACT_VENTAS` v WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_CLIENTE`   d WHERE d.id_cliente   = v.id_cliente)   UNION ALL
SELECT 'sin_dim_vendedor',                 COUNT(*) FROM `sing1261.ali1_curated.FACT_VENTAS` v WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_VENDEDOR`  d WHERE d.id_vendedor  = v.id_vendedor)  UNION ALL
SELECT 'sin_dim_almacen',                  COUNT(*) FROM `sing1261.ali1_curated.FACT_VENTAS` v WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_ALMACEN`   d WHERE d.id_almacen   = v.id_almacen)   UNION ALL
SELECT 'sin_dim_geografia',                COUNT(*) FROM `sing1261.ali1_curated.FACT_VENTAS` v WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_GEOGRAFIA` d WHERE d.id_geografia = v.id_geografia);


-- -----------------------------------------------------------------------------
-- E-CUR-09: FACT_INVENTARIO — integridad referencial
-- Esperado: 0 claves foráneas huérfanas
-- -----------------------------------------------------------------------------
SELECT 'sin_dim_tiempo'   AS check_nombre, COUNT(*) AS huerfanos FROM `sing1261.ali1_curated.FACT_INVENTARIO` i WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_TIEMPO`   d WHERE d.id_fecha   = i.id_fecha)   UNION ALL
SELECT 'sin_dim_producto',                 COUNT(*) FROM `sing1261.ali1_curated.FACT_INVENTARIO` i WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_PRODUCTO` d WHERE d.id_producto = i.id_producto) UNION ALL
SELECT 'sin_dim_almacen',                  COUNT(*) FROM `sing1261.ali1_curated.FACT_INVENTARIO` i WHERE NOT EXISTS (SELECT 1 FROM `sing1261.ali1_curated.DIM_ALMACEN`  d WHERE d.id_almacen  = i.id_almacen);


-- -----------------------------------------------------------------------------
-- E-CUR-10: FACT_VENTAS — métricas financieras sin valores negativos inesperados
-- Esperado: ventas_netas_soles y cantidad_vendida siempre > 0
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(ventas_netas_soles <= 0)  AS ventas_netas_no_positivas,
  COUNTIF(cantidad_vendida <= 0)    AS cantidad_no_positiva,
  COUNTIF(costo_ventas_soles < 0)   AS costo_negativo,
  MIN(ventas_netas_soles)           AS min_ventas_netas,
  MAX(ventas_netas_soles)           AS max_ventas_netas,
  ROUND(AVG(ventas_netas_soles), 2) AS avg_ventas_netas
FROM `sing1261.ali1_curated.FACT_VENTAS`;


-- -----------------------------------------------------------------------------
-- E-CUR-11: FACT_VENTAS — devoluciones imputadas desde trusted.devoluciones
-- Esperado: suma de unidades_devueltas en curated = suma de cantidad_devuelta en trusted
-- -----------------------------------------------------------------------------
SELECT
  (SELECT SUM(unidades_devueltas) FROM `sing1261.ali1_curated.FACT_VENTAS`)         AS curated_devueltas,
  (SELECT SUM(cantidad_devuelta)  FROM `sing1261.ali1_trusted.devoluciones`)         AS trusted_devueltas;


-- -----------------------------------------------------------------------------
-- E-CUR-12: FACT_VENTAS — muestra de 5 registros para inspección visual
-- -----------------------------------------------------------------------------
SELECT
  id_venta, num_factura, id_fecha, id_cliente, id_producto,
  id_canal, id_vendedor, id_almacen,
  cantidad_vendida, ventas_netas_soles, costo_ventas_soles,
  unidades_devueltas, monto_devuelto_soles
FROM `sing1261.ali1_curated.FACT_VENTAS`
LIMIT 5;


-- -----------------------------------------------------------------------------
-- E-CUR-13: FACT_INVENTARIO — sin stock negativo (heredado de trusted)
-- Esperado: 0 registros con stock_disponible < 0
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(stock_disponible < 0) AS registros_stock_negativo,
  MIN(stock_disponible)         AS stock_minimo
FROM `sing1261.ali1_curated.FACT_INVENTARIO`;


-- -----------------------------------------------------------------------------
-- E-CUR-14: FACT_METAS_COMERCIAL — cobertura por canal y período
-- Esperado: cada canal tiene metas para todos los períodos del histórico
-- -----------------------------------------------------------------------------
SELECT
  id_canal,
  COUNT(DISTINCT periodo) AS periodos_con_meta,
  MIN(periodo)            AS periodo_min,
  MAX(periodo)            AS periodo_max
FROM `sing1261.ali1_curated.FACT_METAS_COMERCIAL`
GROUP BY id_canal
ORDER BY id_canal;


-- -----------------------------------------------------------------------------
-- E-CUR-15: DIM_CLIENTE — fecha_primer_compra derivada correctamente
-- Esperado: fecha_primer_compra entre 2023 y 2025, sin fechas futuras
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(fecha_primer_compra IS NULL)       AS sin_compra,
  COUNTIF(fecha_primer_compra < '2023-01-01') AS anterior_a_2023,
  COUNTIF(fecha_primer_compra > CURRENT_DATE()) AS fecha_futura,
  MIN(fecha_primer_compra)                   AS primer_compra_min,
  MAX(fecha_primer_compra)                   AS primer_compra_max
FROM `sing1261.ali1_curated.DIM_CLIENTE`;
