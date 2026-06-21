# Documentación de Modelos Predictivos v2 — Proyecto Ali1
**Proyecto GCP**: sing1261
**Dataset**: ali1_predictive
**Fecha de ejecución**: 2026-06-21

> Esta es la versión **v2** de los modelos. Convive con la v1
> ([documentacion_modelos.md](documentacion_modelos.md)) sin reemplazarla: todos los
> objetos llevan sufijo `_v2` y se generan con el procedimiento
> `sp_etl_predictive_v2` ([etl_predictive_v2.sql](etl_predictive_v2.sql)).

---

## ¿Por qué la capa predictiva sale de `curated` y no de `kpi`?

`ali1_kpi` y `ali1_predictive` son **consumidores hermanos** de `ali1_curated`, no una
cadena. La capa predictiva **debe** leer del modelo estrella (`curated`), no de los cubos
(`kpi`), porque:

1. **Grano atómico.** Los cubos de `kpi` vienen pre-agregados; el clasificador de quiebre
   necesita los `LAG()` por `id_producto × id_almacen` del grano de `FACT_INVENTARIO`, que
   no se puede reconstruir desde `CUBO_INVENTARIO_TBL`.
2. **Sin sesgo de muestra.** `CUBO_COMERCIAL_TBL` hace `INNER JOIN` con
   `FACT_METAS_COMERCIAL` y descarta filas sin meta — entrenar sobre eso sesgaría el modelo.
3. **Semántica limpia.** Los cubos mezclan medidas aditivas (`SUM`) con no aditivas (`MAX`
   de metas); como fuente de features eso es impuro.

La arquitectura original (predictive ← curated) ya era correcta y **no se modificó**.

---

## Modelo 1 v2: Pronóstico de Ventas por Canal (ARIMA_PLUS_XREG)

### Cambio respecto a v1
v1 usaba **ARIMA_PLUS** (univariante: la serie se explica solo a sí misma). v2 usa
**ARIMA_PLUS_XREG**, que incorpora **regresores externos** ya disponibles en el histórico:

| Regresor | Fuente | Cobertura histórica (validada) |
|---|---|---|
| `es_feriado` | `DIM_TIEMPO.es_feriado` | 36 feriados Perú × 6 canales |
| `inversion_promo` | `FACT_VENTAS.inversion_promocional_soles` | 0% nulos, 0% ceros, prom. S/2,028 |

### Variable objetivo
`ventas_netas_soles` — suma diaria de ventas netas por canal (S/.)

**Tabla de entrenamiento**: `train_ventas_forecast_v2` (6,576 filas = 1,096 días × 6 canales)
**Regresores futuros**: `future_regressors_v2` (540 filas = 90 días Q1-2026 × 6 canales)

### Manejo de regresores futuros
`ARIMA_PLUS_XREG` requiere valores **futuros** de los regresores para pronosticar:
- `es_feriado`: determinista a partir del calendario Perú (en Q1-2026 solo Año Nuevo, 1-ene).
- `inversion_promo`: **supuesto de planificación** = promedio histórico por `id_canal × mes`.
  Es una **palanca what-if**: cambiar los valores de `future_regressors_v2` permite simular
  escenarios de inversión promocional distintos sin reentrenar el modelo.

### Algoritmo
`CREATE MODEL ... OPTIONS(model_type='ARIMA_PLUS_XREG', time_series_timestamp_col='ds',
time_series_data_col='ventas_netas_soles', time_series_id_col='id_canal', horizon=90,
auto_arima=TRUE, data_frequency='AUTO_FREQUENCY')`.
Nota: `decompose_time_series` **no** es soportado por ARIMA_PLUS_XREG (se omite).

### Resultados — AIC v1 vs v2 (menor = mejor)
| Canal | AIC v1 | AIC v2 | Mejora |
|---|---|---|---|
| 1 | 25,412.4 | 24,470.7 | −941.7 |
| 2 | 25,789.6 | 24,197.1 | −1,592.5 |
| 3 | 25,266.9 | 24,281.1 | −985.8 |
| 4 | 25,863.2 | 24,362.9 | −1,500.3 |
| 5 | 25,253.8 | 24,401.2 | −852.6 |
| 6 | 25,476.3 | 24,389.5 | −1,086.7 |

**Mejora consistente en los 6 canales** (entre 850 y 1,600 puntos de AIC). Los regresores
aportan información real que la serie univariante no capturaba.

### Forecast Q1-2026 (más estrecho que v1)
| Canal | Venta diaria media (S/.) | IC 90% (±S/.) | IC 90% v1 (ref.) |
|---|---|---|---|
| 1 | 117,861 | ±27,986 | ±43,304 |
| 2 | 109,793 | ±24,941 | ±57,241 |
| 3 | 109,622 | ±25,667 | ±40,675 |
| 4 | 112,392 | ±26,642 | ±53,658 |
| 5 | 113,301 | ±27,301 | ±40,320 |
| 6 | 120,364 | ±26,984 | ±44,585 |

Los intervalos de confianza se reducen ~40% frente a v1: el modelo es más preciso porque
explica parte de la varianza con feriados e inversión promocional.

### Tablas generadas
`train_ventas_forecast_v2`, `future_regressors_v2`, `model_ventas_forecast_v2`,
`eval_ventas_forecast_v2`, `pred_ventas_forecast_v2`.

---

## Modelo 2 v2: Clasificación de Quiebre de Stock (BOOSTED_TREE_CLASSIFIER)

### Cambio respecto a v1
El modelo, las features y el split temporal son **idénticos** a v1. El cambio es una
**corrección de la evaluación**:

> **Bug en v1**: el bloque de evaluación llamaba a `ML.EVALUATE` sobre **toda**
> `train_quiebre_stock` (train 2023-24 **+** holdout 2025). Como el modelo ya vio el train,
> las métricas reportadas estaban **infladas**.
>
> **Fix en v2**: `ML.EVALUATE` se ejecuta **solo sobre el holdout 2025** (`WHERE split = TRUE`,
> 13,464 filas no vistas en entrenamiento). Las métricas resultantes son las **reales**.

### Variable objetivo y features
Sin cambios respecto a v1 (todas las features del período anterior T-1 para evitar leakage):
`stock_mes_anterior`, `reservado_mes_anterior`, `cobertura_mes_anterior`,
`demanda_mes_anterior`, `tendencia_stock`, `quiebres_ultimos_3_meses`, `categoria`,
`linea_negocio`, `tipo_almacen`, `macroregion`, `mes`, `trimestre`.

**Split**: 2023-2024 = TRAIN (25,846 filas) / 2025 = EVAL holdout (13,464 filas).

### Métricas — v1 (con leakage) vs v2 (holdout real)
| Métrica | v1 (toda la tabla) | v2 (holdout 2025) |
|---|---|---|
| Precision | 54.28% | **47.13%** |
| Recall | 99.91% | **99.65%** |
| F1-Score | 70.34% | **63.99%** |
| ROC-AUC | 98.53% | **97.74%** |
| Accuracy | 95.46% | **95.20%** |

Las métricas honestas de v2 son algo más bajas (lo esperado al eliminar el leakage de
evaluación), pero siguen siendo **fuertes**: ROC-AUC 97.7% y recall 99.6%. El recall casi
total es el comportamiento correcto para alertas de inventario — es preferible una falsa
alarma a un stock-out. El ROC-AUC alto confirma buena discriminación al ajustar el umbral.

### Tablas generadas
`train_quiebre_stock_v2`, `model_quiebre_stock_v2`, `eval_quiebre_stock_v2`,
`pred_quiebre_stock_v2`.

---

## Equivalencia v1 ↔ v2

| Concepto | v1 | v2 |
|---|---|---|
| Procedimiento | `sp_etl_predictive` | `sp_etl_predictive_v2` |
| Script SQL | `etl_predictive.sql` | `etl_predictive_v2.sql` |
| Runner Python | `run_etl_predictive.py` | `run_etl_predictive_v2.py` |
| Forecast — algoritmo | ARIMA_PLUS | ARIMA_PLUS_XREG (+ regresores) |
| Forecast — tablas | `*_ventas_forecast` | `*_ventas_forecast_v2` (+ `future_regressors_v2`) |
| Clasificador — evaluación | toda la tabla (leakage) | solo holdout 2025 |
| Clasificador — tablas | `*_quiebre_stock` | `*_quiebre_stock_v2` |

Ambas versiones coexisten en `sing1261.ali1_predictive` y registran su ejecución en la misma
tabla de control `etl_control`.

### Cómo ejecutar
```bash
python run_etl_predictive_v2.py
```

---

## Servicio cloud usado
**BigQuery ML** (Google Cloud Platform)
Funciones: `CREATE MODEL` (ARIMA_PLUS_XREG / BOOSTED_TREE_CLASSIFIER),
`ML.ARIMA_EVALUATE`, `ML.FORECAST` (con regresores futuros), `ML.EVALUATE`, `ML.PREDICT`.
Dataset: `sing1261.ali1_predictive`.
