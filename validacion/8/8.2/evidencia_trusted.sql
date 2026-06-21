-- =============================================================================
-- EVIDENCIA ELT — CAPA TRUSTED
-- Dataset: sing1261.ali1_trusted
-- Ejecutar después de: CALL `sing1261.ali1_trusted.sp_etl_trusted`()
-- =============================================================================


-- -----------------------------------------------------------------------------
-- E-TRU-01: Estado del ETL — todas las tablas cargaron sin error
-- Esperado: 0 filas con estado = 'ERROR'
-- -----------------------------------------------------------------------------
SELECT
  tabla_destino,
  tipo,
  estado,
  registros_cargados,
  mensaje_error,
  fecha_carga
FROM `sing1261.ali1_trusted.etl_control`
WHERE estado = 'ERROR'
ORDER BY fecha_carga DESC;


-- -----------------------------------------------------------------------------
-- E-TRU-02: Resumen de carga — 15 tablas con registros > 0
-- Esperado: todas las tablas en estado EXITOSO
-- -----------------------------------------------------------------------------
SELECT
  tabla_destino,
  estado,
  registros_cargados,
  fecha_carga
FROM `sing1261.ali1_trusted.etl_control`
WHERE estado = 'EXITOSO'
ORDER BY tabla_destino;


-- -----------------------------------------------------------------------------
-- E-TRU-03: Ventas — regla VQ-01: cero registros con estado_linea = 'DUPLICADO'
-- Esperado: 0 filas (trusted solo carga estado_linea <> 'DUPLICADO')
-- -----------------------------------------------------------------------------
SELECT
  estado_linea,
  COUNT(*) AS registros
FROM `sing1261.ali1_trusted.ventas`
WHERE estado_linea = 'DUPLICADO'
GROUP BY estado_linea;


-- -----------------------------------------------------------------------------
-- E-TRU-04: Ventas — comparativo raw vs trusted (reducción por deduplicación)
-- Esperado: trusted < raw exactamente en la cantidad de DUPLICADO de raw
-- -----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `sing1261.ali1_raw.ventas`)                              AS raw_total,
  (SELECT COUNT(*) FROM `sing1261.ali1_trusted.ventas`)                          AS trusted_total,
  (SELECT COUNT(*) FROM `sing1261.ali1_raw.ventas` WHERE estado_linea = 'DUPLICADO') AS raw_duplicados,
  (SELECT COUNT(*) FROM `sing1261.ali1_raw.ventas`) -
  (SELECT COUNT(*) FROM `sing1261.ali1_trusted.ventas`)                          AS diferencia;


-- -----------------------------------------------------------------------------
-- E-TRU-05: Ventas — sufijo _DUP eliminado de id_linea_venta
-- Esperado: 0 registros con id_linea_venta terminando en '_DUP'
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS registros_con_sufijo_dup
FROM `sing1261.ali1_trusted.ventas`
WHERE ENDS_WITH(id_linea_venta, '_DUP');


-- -----------------------------------------------------------------------------
-- E-TRU-06: Inventario — regla VQ-02: cero registros con stock_disponible < 0
-- Esperado: 0 filas
-- -----------------------------------------------------------------------------
SELECT
  COUNT(*) AS registros_stock_negativo,
  MIN(stock_disponible) AS stock_minimo
FROM `sing1261.ali1_trusted.inventario`
WHERE stock_disponible < 0;


-- -----------------------------------------------------------------------------
-- E-TRU-07: Inventario — comparativo raw vs trusted (reducción por stock negativo)
-- Esperado: trusted < raw en la cantidad de registros con stock < 0
-- -----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `sing1261.ali1_raw.inventario`)                              AS raw_total,
  (SELECT COUNT(*) FROM `sing1261.ali1_trusted.inventario`)                          AS trusted_total,
  (SELECT COUNT(*) FROM `sing1261.ali1_raw.inventario` WHERE stock_disponible < 0)  AS raw_negativos,
  (SELECT COUNT(*) FROM `sing1261.ali1_raw.inventario`) -
  (SELECT COUNT(*) FROM `sing1261.ali1_trusted.inventario`)                          AS diferencia;


-- -----------------------------------------------------------------------------
-- E-TRU-08: Fill rate — regla VQ-04: sin NULLs en transportista ni motivo_rechazo
-- Esperado: 0 nulos en ambos campos (imputados con 'No especificado')
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(transportista IS NULL)  AS nulos_transportista,
  COUNTIF(motivo_rechazo IS NULL) AS nulos_motivo_rechazo,
  COUNTIF(transportista = 'No especificado')  AS imputados_transportista,
  COUNTIF(motivo_rechazo = 'No especificado') AS imputados_motivo_rechazo
FROM `sing1261.ali1_trusted.fill_rate`;


-- -----------------------------------------------------------------------------
-- E-TRU-09: Metas — solo versiones aprobadas (es_version_aprobada = 1)
-- Esperado: 0 filas con es_version_aprobada = 0
-- -----------------------------------------------------------------------------
SELECT
  es_version_aprobada,
  COUNT(*) AS registros
FROM `sing1261.ali1_trusted.metas`
GROUP BY es_version_aprobada;


-- -----------------------------------------------------------------------------
-- E-TRU-10: Promociones — flag_sap_id_pendiente creado correctamente
-- Esperado: flag = 1 en registros donde id_promocion_sap era NULL o vacío
-- -----------------------------------------------------------------------------
SELECT
  flag_sap_id_pendiente,
  COUNT(*)                                             AS registros,
  COUNTIF(id_promocion_sap IS NULL OR id_promocion_sap = '') AS sin_id_sap
FROM `sing1261.ali1_trusted.promociones`
GROUP BY flag_sap_id_pendiente
ORDER BY flag_sap_id_pendiente;


-- -----------------------------------------------------------------------------
-- E-TRU-11: Productos — sufijo _DUP eliminado de cod_sap
-- Esperado: 0 registros con cod_sap terminando en '_DUP'
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS registros_con_sufijo_dup
FROM `sing1261.ali1_trusted.productos`
WHERE ENDS_WITH(cod_sap, '_DUP');


-- -----------------------------------------------------------------------------
-- E-TRU-12: Clientes — flag_direccion_completa creado
-- Esperado: distribución coherente (1 = tiene dirección, 0 = sin dirección)
-- -----------------------------------------------------------------------------
SELECT
  flag_direccion_completa,
  COUNT(*) AS clientes
FROM `sing1261.ali1_trusted.clientes`
GROUP BY flag_direccion_completa
ORDER BY flag_direccion_completa;


-- -----------------------------------------------------------------------------
-- E-TRU-13: Integridad referencial ventas → clientes y productos
-- Esperado: 0 registros huérfanos (id_cliente o id_producto sin maestro)
-- -----------------------------------------------------------------------------
SELECT
  'clientes_huerfanos' AS check_nombre,
  COUNT(*) AS registros
FROM `sing1261.ali1_trusted.ventas` v
WHERE NOT EXISTS (
  SELECT 1 FROM `sing1261.ali1_trusted.clientes` c
  WHERE CAST(REGEXP_EXTRACT(c.id_cliente_raw, r'\d+$') AS INT64) = v.id_cliente
)
UNION ALL
SELECT
  'productos_huerfanos',
  COUNT(*)
FROM `sing1261.ali1_trusted.ventas` v
WHERE NOT EXISTS (
  SELECT 1 FROM `sing1261.ali1_trusted.productos` p
  WHERE CAST(REGEXP_EXTRACT(p.id_producto_raw, r'\d+$') AS INT64) = v.id_producto
);
