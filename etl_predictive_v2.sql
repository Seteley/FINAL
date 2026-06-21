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
  -- MODELO 2 v2: CLASIFICACIÓN DE QUIEBRE DE STOCK (BOOSTED_TREE_CLASSIFIER)
  -- Igual que v1 PERO con la evaluación corregida: se evalúa SOLO sobre el
  -- holdout 2025 (split = TRUE), no sobre toda la tabla de entrenamiento.
  -- Split temporal: 2023-2024 = TRAIN, 2025 = EVAL
  -- =========================================================

  -- Bloque 6: Tabla de entrenamiento — lag features sin leakage (idéntico a v1)
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_predictive.train_quiebre_stock_v2` AS
    WITH inv_lag AS (
      SELECT
        fi.id_producto,
        fi.id_almacen,
        fi.id_fecha,
        fi.flag_quiebre,
        LAG(fi.stock_disponible, 1)    OVER (PARTITION BY fi.id_producto, fi.id_almacen ORDER BY fi.id_fecha) AS stock_mes_anterior,
        LAG(fi.stock_reservado, 1)     OVER (PARTITION BY fi.id_producto, fi.id_almacen ORDER BY fi.id_fecha) AS reservado_mes_anterior,
        LAG(fi.dias_cobertura, 1)      OVER (PARTITION BY fi.id_producto, fi.id_almacen ORDER BY fi.id_fecha) AS cobertura_mes_anterior,
        LAG(fi.demanda_diaria_prom, 1) OVER (PARTITION BY fi.id_producto, fi.id_almacen ORDER BY fi.id_fecha) AS demanda_mes_anterior,
        fi.stock_disponible - LAG(fi.stock_disponible, 1)
          OVER (PARTITION BY fi.id_producto, fi.id_almacen ORDER BY fi.id_fecha)                              AS tendencia_stock,
        SUM(fi.flag_quiebre) OVER (
          PARTITION BY fi.id_producto, fi.id_almacen
          ORDER BY fi.id_fecha
          ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        )                                                                                                      AS quiebres_ultimos_3_meses
      FROM `sing1261.ali1_curated.FACT_INVENTARIO` fi
    )
    SELECT
      il.flag_quiebre,
      il.stock_mes_anterior,
      il.reservado_mes_anterior,
      il.cobertura_mes_anterior,
      il.demanda_mes_anterior,
      il.tendencia_stock,
      il.quiebres_ultimos_3_meses,
      dp.categoria,
      dp.linea_negocio,
      da.tipo_almacen,
      da.macroregion,
      dt.mes,
      dt.trimestre,
      EXTRACT(YEAR FROM dt.fecha) >= 2025 AS split
    FROM inv_lag il
    JOIN `sing1261.ali1_curated.DIM_PRODUCTO` dp ON il.id_producto = dp.id_producto
    JOIN `sing1261.ali1_curated.DIM_ALMACEN`  da ON il.id_almacen  = da.id_almacen
    JOIN `sing1261.ali1_curated.DIM_TIEMPO`   dt ON il.id_fecha    = dt.id_fecha
    WHERE il.stock_mes_anterior IS NOT NULL;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.train_quiebre_stock_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_quiebre_stock_v2', 'TRAIN', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_quiebre_stock_v2', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 7: Entrenamiento modelo BOOSTED_TREE_CLASSIFIER (split temporal custom)
  BEGIN
    CREATE OR REPLACE MODEL `sing1261.ali1_predictive.model_quiebre_stock_v2`
    OPTIONS(
      model_type            = 'BOOSTED_TREE_CLASSIFIER',
      input_label_cols      = ['flag_quiebre'],
      data_split_method     = 'CUSTOM',
      data_split_col        = 'split',
      auto_class_weights    = TRUE,
      num_parallel_tree     = 4,
      max_iterations        = 100,
      enable_global_explain = TRUE
    )
    AS SELECT * FROM `sing1261.ali1_predictive.train_quiebre_stock_v2`;

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_quiebre_stock_v2', 'TRAIN', 'EXITOSO', 1, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_quiebre_stock_v2', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 8 (CORREGIDO): Evaluación SOLO sobre el holdout 2025 (split = TRUE)
  --   v1 evaluaba sobre la tabla completa (train + holdout) → métricas infladas.
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.eval_quiebre_stock_v2` AS
      SELECT * FROM ML.EVALUATE(
        MODEL `sing1261.ali1_predictive.model_quiebre_stock_v2`,
        (SELECT * FROM `sing1261.ali1_predictive.train_quiebre_stock_v2` WHERE split = TRUE)
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.eval_quiebre_stock_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_quiebre_stock_v2', 'EVALUATE', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_quiebre_stock_v2', 'EVALUATE', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 9: Predicciones — scoring completo del dataset
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.pred_quiebre_stock_v2` AS
      SELECT * FROM ML.PREDICT(
        MODEL `sing1261.ali1_predictive.model_quiebre_stock_v2`,
        (SELECT * EXCEPT(flag_quiebre, split)
         FROM `sing1261.ali1_predictive.train_quiebre_stock_v2`)
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.pred_quiebre_stock_v2`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_quiebre_stock_v2', 'PREDICT', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_quiebre_stock_v2', 'PREDICT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

END;
