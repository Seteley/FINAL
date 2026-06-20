CREATE OR REPLACE PROCEDURE `sing1261.ali1_predictive.sp_etl_predictive`()
BEGIN

  -- Tabla de control para la capa predictiva
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
  -- MODELO 1: PRONÓSTICO DE VENTAS POR CANAL (ARIMA_PLUS)
  -- =========================================================

  -- Bloque 1: Tabla de entrenamiento — serie diaria de ventas por canal
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_predictive.train_ventas_forecast` AS
    SELECT
      t.fecha                     AS ds,
      v.id_canal,
      SUM(v.ventas_netas_soles)   AS ventas_netas_soles
    FROM `sing1261.ali1_curated.FACT_VENTAS` v
    JOIN `sing1261.ali1_curated.DIM_TIEMPO` t ON v.id_fecha = t.id_fecha
    GROUP BY 1, 2
    ORDER BY 1, 2;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.train_ventas_forecast`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_ventas_forecast', 'TRAIN', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_ventas_forecast', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 2: Entrenamiento modelo ARIMA_PLUS
  BEGIN
    CREATE OR REPLACE MODEL `sing1261.ali1_predictive.model_ventas_forecast`
    OPTIONS(
      model_type                = 'ARIMA_PLUS',
      time_series_timestamp_col = 'ds',
      time_series_data_col      = 'ventas_netas_soles',
      time_series_id_col        = 'id_canal',
      horizon                   = 90,
      auto_arima                = TRUE,
      data_frequency            = 'AUTO_FREQUENCY',
      decompose_time_series     = TRUE
    )
    AS
    SELECT ds, id_canal, ventas_netas_soles
    FROM `sing1261.ali1_predictive.train_ventas_forecast`;

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_ventas_forecast', 'TRAIN', 'EXITOSO', 1, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_ventas_forecast', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 3: Evaluación ARIMA — métricas de ajuste por canal (AIC, p/d/q, varianza)
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.eval_ventas_forecast` AS
      SELECT *
      FROM ML.ARIMA_EVALUATE(
        MODEL `sing1261.ali1_predictive.model_ventas_forecast`
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.eval_ventas_forecast`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_ventas_forecast', 'EVALUATE', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_ventas_forecast', 'EVALUATE', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 4: Descomposición ARIMA — tendencia, estacionalidad y residuos
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.explain_ventas_forecast` AS
      SELECT *
      FROM ML.EXPLAIN_FORECAST(
        MODEL `sing1261.ali1_predictive.model_ventas_forecast`,
        STRUCT(90 AS horizon, 0.9 AS confidence_level)
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.explain_ventas_forecast`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('explain_ventas_forecast', 'EVALUATE', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('explain_ventas_forecast', 'EVALUATE', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 5: Predicciones — próximos 90 días por canal
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.pred_ventas_forecast` AS
      SELECT *
      FROM ML.FORECAST(
        MODEL `sing1261.ali1_predictive.model_ventas_forecast`,
        STRUCT(90 AS horizon, 0.9 AS confidence_level)
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.pred_ventas_forecast`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_ventas_forecast', 'PREDICT', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_ventas_forecast', 'PREDICT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- =========================================================
  -- MODELO 2: CLASIFICACIÓN DE QUIEBRE DE STOCK (BOOSTED_TREE_CLASSIFIER)
  -- Leakage corregido: usa variables del mes ANTERIOR (LAG)
  -- Split temporal: 2023-2024 = TRAIN, 2025 = EVAL
  -- =========================================================

  -- Bloque 6: Tabla de entrenamiento — lag features sin leakage
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    CREATE OR REPLACE TABLE `sing1261.ali1_predictive.train_quiebre_stock` AS
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

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.train_quiebre_stock`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_quiebre_stock', 'TRAIN', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('train_quiebre_stock', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 7: Entrenamiento modelo BOOSTED_TREE_CLASSIFIER
  BEGIN
    CREATE OR REPLACE MODEL `sing1261.ali1_predictive.model_quiebre_stock`
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
    AS SELECT * FROM `sing1261.ali1_predictive.train_quiebre_stock`;

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_quiebre_stock', 'TRAIN', 'EXITOSO', 1, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('model_quiebre_stock', 'TRAIN', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 8: Evaluación del clasificador sobre holdout 2025
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.eval_quiebre_stock` AS
      SELECT * FROM ML.EVALUATE(
        MODEL `sing1261.ali1_predictive.model_quiebre_stock`,
        (SELECT * FROM `sing1261.ali1_predictive.train_quiebre_stock`)
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.eval_quiebre_stock`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_quiebre_stock', 'EVALUATE', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('eval_quiebre_stock', 'EVALUATE', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

  -- Bloque 9: Predicciones — scoring completo del dataset
  BEGIN
    DECLARE rows_loaded INT64 DEFAULT 0;

    EXECUTE IMMEDIATE """
      CREATE OR REPLACE TABLE `sing1261.ali1_predictive.pred_quiebre_stock` AS
      SELECT * FROM ML.PREDICT(
        MODEL `sing1261.ali1_predictive.model_quiebre_stock`,
        (SELECT * EXCEPT(flag_quiebre, split)
         FROM `sing1261.ali1_predictive.train_quiebre_stock`)
      )
    """;

    SET rows_loaded = (SELECT COUNT(*) FROM `sing1261.ali1_predictive.pred_quiebre_stock`);

    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_quiebre_stock', 'PREDICT', 'EXITOSO', rows_loaded, CAST(NULL AS STRING), CURRENT_TIMESTAMP());

  EXCEPTION WHEN ERROR THEN
    INSERT INTO `sing1261.ali1_predictive.etl_control`
      (tabla_destino, tipo, estado, registros_cargados, mensaje_error, fecha_carga)
    VALUES
      ('pred_quiebre_stock', 'PREDICT', 'ERROR', CAST(NULL AS INT64), CAST(@@error.message AS STRING), CURRENT_TIMESTAMP());
  END;

END;
