CREATE OR REPLACE PROCEDURE `sing1261.ali1_predictive.sp_etl_predictive_v2`()
BEGIN

  -- Tabla de control para la capa predictiva (compartida; los nombres *_v2 la diferencian)
  CREATE TABLE IF NOT EXISTS `sing1261.ali1_predictive.etl_control`
  (
    tabla_destino      STRING    NOT NULL,
    tipo               STRING    NOT NULL,
    estado             STRING    NOT NULL,
    registros_cargados INT64,
    mensaje_error      STRING,
    fecha_carga        TIMESTAMP NOT NULL
  );

  -- =========================================================
  -- MODELO 1 v2: PRONÓSTICO DE VENTAS POR CANAL (ARIMA_PLUS_XREG)
  -- Mejora sobre v1: incorpora regresores externos es_feriado e
  -- inversion_promocional_soles (ambos 100% poblados en el histórico).
  -- =========================================================

  -- Bloque 1: Tabla de entrenamiento — serie diaria por canal + regresores
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_predictive.train_ventas_forecast_v2` AS
    SELECT
      t.fecha                              AS ds,
      v.id_canal,
      SUM(v.ventas_netas_soles)            AS ventas_netas_soles,
      SUM(v.inversion_promocional_soles)   AS inversion_promo,
      MAX(t.es_feriado)                    AS es_feriado
    FROM `sing1261.ali1_curated.FACT_VENTAS` v
    JOIN `sing1261.ali1_curated.DIM_TIEMPO` t ON v.id_fecha = t.id_fecha
    GROUP BY 1, 2
    ORDER BY 1, 2;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.train_ventas_forecast_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_ventas_forecast_v2', 'TRAIN', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_ventas_forecast_v2', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 2: Tabla de regresores futuros — 90 días (Q1 2026) × 6 canales
  --   es_feriado: determinista (calendario Perú: Año Nuevo 2026-01-01 dentro de Q1)
  --   inversion_promo: supuesto de planificación = promedio histórico por canal × mes
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_predictive.future_regressors_v2` AS
    WITH fechas AS (
      SELECT fecha AS ds
      FROM UNNEST(GENERATE_DATE_ARRAY('2026-01-01', '2026-03-31')) AS fecha
    ),
    feriados_2026 AS (
      SELECT fecha FROM UNNEST([DATE '2026-01-01']) AS fecha  -- único feriado Perú en Q1 2026
    ),
    canales AS (
      SELECT DISTINCT id_canal FROM `sing1261.ali1_predictive.train_ventas_forecast_v2`
    ),
    promo_baseline AS (
      SELECT
        id_canal,
        EXTRACT(MONTH FROM ds) AS mes,
        AVG(inversion_promo)   AS promo_prom
      FROM `sing1261.ali1_predictive.train_ventas_forecast_v2`
      WHERE EXTRACT(MONTH FROM ds) IN (1, 2, 3)
      GROUP BY 1, 2
    )
    SELECT
      f.ds,
      c.id_canal,
      COALESCE(pb.promo_prom, 0)                          AS inversion_promo,
      IF(fer.fecha IS NOT NULL, 1, 0)                     AS es_feriado
    FROM fechas f
    CROSS JOIN canales c
    LEFT JOIN feriados_2026 fer ON f.ds = fer.fecha
    LEFT JOIN promo_baseline pb
      ON c.id_canal = pb.id_canal AND EXTRACT(MONTH FROM f.ds) = pb.mes;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.future_regressors_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('future_regressors_v2', 'TRAIN', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('future_regressors_v2', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 3: Entrenamiento modelo ARIMA_PLUS_XREG (regresores como columnas extra)
  BEGIN
    CREATE OR REPLACE MODEL `sing1261.ali1_predictive.model_ventas_forecast_v2`
    OPTIONS(
      model_type                = 'ARIMA_PLUS_XREG',
      time_series_timestamp_col = 'ds',
      time_series_data_col      = 'ventas_netas_soles',
      time_series_id_col        = 'id_canal',
      horizon                   = 90,
      auto_arima                = TRUE,
      data_frequency            = 'AUTO_FREQUENCY'
    )
    AS
    SELECT ds, id_canal, ventas_netas_soles, inversion_promo, es_feriado
    FROM `sing1261.ali1_predictive.train_ventas_forecast_v2`;

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_ventas_forecast_v2', 'TRAIN', 'EXITOSO', 1, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_ventas_forecast_v2', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 4: Evaluación ARIMA — métricas de ajuste por canal (AIC, p/d/q, varianza)
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.eval_ventas_forecast_v2` AS
      SELECT *
      FROM ML.ARIMA_EVALUATE(
        MODEL `sing1261.ali1_predictive.model_ventas_forecast_v2`
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.eval_ventas_forecast_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_ventas_forecast_v2', 'EVALUATE', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_ventas_forecast_v2', 'EVALUATE', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 5: Predicciones — próximos 90 días por canal usando regresores futuros
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.pred_ventas_forecast_v2` AS
      SELECT *
      FROM ML.FORECAST(
        MODEL `sing1261.ali1_predictive.model_ventas_forecast_v2`,
        STRUCT(90 AS horizon, 0.9 AS confidence_level),
        (
          SELECT ds, id_canal, inversion_promo, es_feriado
          FROM `sing1261.ali1_predictive.future_regressors_v2`
        )
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.pred_ventas_forecast_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_ventas_forecast_v2', 'PREDICT', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_ventas_forecast_v2', 'PREDICT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- MODELO 2 v2: SEGMENTACIÓN DE PRODUCTOS (KMEANS)
  -- Reemplaza al clasificador de quiebre v1/v2: en este dataset los eventos de
  -- riesgo (quiebre, devolución, bajo margen) no tienen señal predecible, pero los
  -- productos SÍ tienen estructura real (precio, margen y rotación muy variables).
  -- K-MEANS agrupa los SKU en segmentos de portafolio (tipo ABC) de forma descriptiva.
  -- =========================================================

  -- Bloque 6: Tabla de features por SKU (precio, margen, rotación, ventas, devolución)
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_predictive.train_segmentacion_productos_v2` AS
    SELECT
      p.id_producto,
      p.cod_sku,
      p.nombre_sku,
      p.categoria,
      p.linea_negocio,
      p.precio_lista_soles,
      ROUND(SAFE_DIVIDE(p.precio_lista_soles - p.costo_estandar_soles, p.precio_lista_soles) * 100, 2) AS margen_pct,
      COALESCE(SUM(v.cantidad_vendida), 0)                                                              AS unidades_vendidas,
      COALESCE(SUM(v.ventas_netas_soles), 0)                                                            AS ventas_netas,
      ROUND(COALESCE(SAFE_DIVIDE(SUM(v.unidades_devueltas), NULLIF(SUM(v.cantidad_vendida), 0)) * 100, 0), 2) AS tasa_devolucion_pct
    FROM `sing1261.ali1_curated.DIM_PRODUCTO` p
    LEFT JOIN `sing1261.ali1_curated.FACT_VENTAS` v ON p.id_producto = v.id_producto
    GROUP BY
      p.id_producto, p.cod_sku, p.nombre_sku, p.categoria, p.linea_negocio,
      p.precio_lista_soles, p.costo_estandar_soles;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.train_segmentacion_productos_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_segmentacion_productos_v2', 'TRAIN', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_segmentacion_productos_v2', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 7: Entrenamiento modelo KMEANS (4 clusters, features estandarizadas)
  BEGIN
    CREATE OR REPLACE MODEL `sing1261.ali1_predictive.model_segmentacion_productos_v2`
    OPTIONS(
      model_type          = 'KMEANS',
      num_clusters        = 4,
      standardize_features = TRUE
    )
    AS
    SELECT precio_lista_soles, margen_pct, unidades_vendidas, ventas_netas, tasa_devolucion_pct
    FROM `sing1261.ali1_predictive.train_segmentacion_productos_v2`;

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_segmentacion_productos_v2', 'TRAIN', 'EXITOSO', 1, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_segmentacion_productos_v2', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 8: Evaluación del clustering (Davies-Bouldin, distancia media)
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.eval_segmentacion_productos_v2` AS
      SELECT * FROM ML.EVALUATE(
        MODEL `sing1261.ali1_predictive.model_segmentacion_productos_v2`
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.eval_segmentacion_productos_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_segmentacion_productos_v2', 'EVALUATE', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_segmentacion_productos_v2', 'EVALUATE', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 9: Asignación de cada SKU a su segmento (cluster)
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.pred_segmentacion_productos_v2` AS
      SELECT
        CENTROID_ID AS cluster,
        id_producto, cod_sku, nombre_sku, categoria, linea_negocio,
        precio_lista_soles, margen_pct, unidades_vendidas, ventas_netas, tasa_devolucion_pct
      FROM ML.PREDICT(
        MODEL `sing1261.ali1_predictive.model_segmentacion_productos_v2`,
        (SELECT * FROM `sing1261.ali1_predictive.train_segmentacion_productos_v2`)
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.pred_segmentacion_productos_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_segmentacion_productos_v2', 'PREDICT', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_segmentacion_productos_v2', 'PREDICT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

END;
