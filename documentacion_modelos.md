# Documentación de Modelos Predictivos — Proyecto Ali1
**Proyecto GCP**: sing1261  
**Dataset**: ali1_predictive  
**Fecha de ejecución**: 2026-06-20  

---

## Modelo 1: Pronóstico de Ventas por Canal

### Objetivo del modelo
Predecir las ventas netas diarias (en soles) para cada canal de venta durante los próximos 90 días, con el fin de anticipar la demanda y planificar recursos comerciales y logísticos.

### Variable objetivo
`ventas_netas_soles` — suma diaria de ventas netas por canal (S/.)

### Variables explicativas
| Variable | Descripción |
|---|---|
| `ds` | Fecha del día (serie temporal) |
| `id_canal` | Identificador del canal de venta (1-6) |
| `ventas_netas_soles` | Valor histórico de la serie (la serie es el propio input del modelo) |

El modelo ARIMA_PLUS extrae automáticamente la estructura interna de la serie: tendencia, estacionalidad, autocorrelación y outliers. No requiere variables externas adicionales.

**Tabla de entrenamiento**: `ali1_predictive.train_ventas_forecast`  
**Período histórico**: 2023-01-01 → 2025-12-31 (1,096 días × 6 canales = 6,576 observaciones)

### Algoritmo
**ARIMA_PLUS** — BigQuery ML  
Modelo autorregresivo integrado de media móvil con componentes adicionales (detección automática de outliers, cambios de nivel y estacionalidad). Parámetros seleccionados automáticamente por `auto_arima=TRUE` por cada serie.

| Canal | p (AR) | d (diferenciación) | q (MA) | AIC | Error típico (S/.) |
|---|---|---|---|---|---|
| 5 | 1 | 1 | 1 | 25,254 ✓ | 24,479 |
| 3 | 0 | 1 | 1 | 25,267 | 24,686 |
| 1 | 0 | 1 | 1 | 25,412 | 26,343 |
| 6 | 0 | 1 | 1 | 25,476 | 27,123 |
| 2 | 1 | 1 | 1 | 25,790 | 31,367 |
| 4 | 1 | 1 | 1 | 25,863 | 32,338 |

`d=1` en todos los canales confirma que la serie tiene tendencia (necesita diferenciación). `p,q > 0` indica estructura autoregresiva y de media móvil real, a diferencia del resultado anterior con datos sin tendencia (ARIMA(0,0,0)).

### Métricas de evaluación
| Métrica | Qué mide | Interpretación |
|---|---|---|
| **AIC** | Calidad de ajuste penalizando complejidad | Más bajo = mejor. Rango: 25,254–25,863 |
| **Varianza de residuos (√)** | Error típico del modelo sobre datos históricos | Rango: S/. 24,479–32,338 por día |
| `has_spikes_and_dips` | Detección de valores atípicos | Canales 1, 4 y 6 tienen outliers significativos |
| `has_step_changes` | Detección de cambios bruscos de nivel | Canales 4 y 6 presentaron cambios estructurales |

### Resultado
**Tablas generadas**:
- `eval_ventas_forecast` — 6 filas (1 por canal) con parámetros y métricas de ajuste
- `explain_ventas_forecast` — 7,116 filas con descomposición histórica + forecast (tendencia, estacionalidades, residuos)
- `pred_ventas_forecast` — 540 filas (90 días × 6 canales), enero–marzo 2026

**Forecast enero–marzo 2026**:
| Canal | Venta diaria media forecast (S/.) | Intervalo de confianza (amplitud S/.) |
|---|---|---|
| 1 | 127,594 | ±43,304 |
| 2 | 139,649 | ±57,241 |
| 3 | 121,802 | ±40,675 |
| 4 | 128,381 | ±53,658 |
| 5 | 127,155 | ±40,320 |
| 6 | 138,451 | ±44,585 |

### Servicio cloud usado
**BigQuery ML** (Google Cloud Platform)  
Funciones: `CREATE MODEL` (ARIMA_PLUS), `ML.ARIMA_EVALUATE`, `ML.EXPLAIN_FORECAST`, `ML.FORECAST`  
Dataset: `sing1261.ali1_predictive`

### Decisiones que aporta el modelo
- **Planificación comercial**: metas de venta por canal para el trimestre siguiente con intervalo de confianza al 90%
- **Detección de anomalías**: identifica canales con cambios bruscos o valores atípicos que requieren revisión
- **Comparación de canales**: canal 2 (mayor forecast) vs canal 3 (menor) orienta dónde concentrar esfuerzo comercial
- **Alerta de tendencia**: `d=1` en todos los canales confirma crecimiento sostenido; el modelo proyecta esta tendencia hacia adelante

---

## Modelo 2: Predicción de Quiebre de Stock

### Objetivo del modelo
Predecir si un producto en un almacén determinado entrará en quiebre de stock en el siguiente período, usando información del período anterior (sin leakage). El objetivo es activar alertas de reposición antes de que ocurra la rotura.

### Variable objetivo
`flag_quiebre` — variable binaria (0 = sin quiebre, 1 = quiebre en el período)

### Variables explicativas
| Variable | Descripción | Período |
|---|---|---|
| `stock_mes_anterior` | Unidades disponibles en el snapshot anterior | T-1 |
| `reservado_mes_anterior` | Unidades reservadas en el snapshot anterior | T-1 |
| `cobertura_mes_anterior` | Días de cobertura calculados en el snapshot anterior | T-1 |
| `demanda_diaria_prom` | Demanda diaria promedio histórica del producto | T-1 |
| `tendencia_stock` | Variación de stock entre T-1 y T-2 (positivo = repuesto, negativo = consumo) | T-1 vs T-2 |
| `quiebres_ultimos_3_meses` | Número de quiebres en los 3 períodos previos | Histórico |
| `categoria` | Categoría del producto | Estático |
| `linea_negocio` | Línea de negocio | Estático |
| `tipo_almacen` | Tipo de almacén (central, regional, etc.) | Estático |
| `macroregion` | Macroregión geográfica del almacén | Estático |
| `mes` | Mes del año (estacionalidad) | Contextual |
| `trimestre` | Trimestre (Q1/Q2/Q3/Q4) | Contextual |

> **Nota sobre leakage corregido**: las variables `stock_disponible` y `dias_cobertura` del mismo período fueron excluidas porque están matemáticamente ligadas al label (stock=0 implica quiebre). El modelo usa exclusivamente información del período anterior para simular predicción real.

**Tabla de entrenamiento**: `ali1_predictive.train_quiebre_stock`  
**Split temporal**: 2023-2024 = TRAIN (25,846 filas, 65.7%) / 2025 = EVAL holdout (13,464 filas, 34.3%)

### Algoritmo
**BOOSTED_TREE_CLASSIFIER** — BigQuery ML  
Árbol de decisión potenciado por gradiente. Configuración:
- `auto_class_weights = TRUE` — corrige el desbalance de clases (≈4% quiebre vs 96% sin quiebre)
- `num_parallel_tree = 4` — ensemble de 4 árboles paralelos
- `max_iterations = 100` — iteraciones de boosting
- `enable_global_explain = TRUE` — importancia de variables habilitada
- `data_split_method = 'CUSTOM'` — split temporal 2023-2024/2025

### Métricas de evaluación
Evaluadas sobre el **holdout 2025** (datos no vistos en entrenamiento):

| Métrica | Valor | Qué mide |
|---|---|---|
| **Precision** | 90.58% | De cada 100 alertas de quiebre, 90.6 son reales (falsas alarmas: 9.4%) |
| **Recall** | 99.94% | De cada 100 quiebres reales, el modelo detecta 99.9 |
| **F1-Score** | 95.03% | Balance harmónico entre precision y recall |
| **ROC-AUC** | 99.99% | Capacidad de discriminación entre clases |
| **Accuracy** | 99.55% | Porcentaje de predicciones correctas sobre el total |

> **Interpretación del trade-off Precision/Recall**: el modelo prioriza no perder quiebres reales (Recall ≈ 100%) a costa de generar algunas alertas falsas (10% de las alertas). Para operaciones de inventario este es el balance correcto: es mejor revisar una alerta falsa que sufrir un stock-out.

### Resultado
**Tablas generadas**:
- `train_quiebre_stock` — 39,310 filas con features de lag + columna split
- `eval_quiebre_stock` — 1 fila con métricas del holdout 2025
- `pred_quiebre_stock` — 39,310 filas con `predicted_flag_quiebre` y probabilidades por registro

### Servicio cloud usado
**BigQuery ML** (Google Cloud Platform)  
Funciones: `CREATE MODEL` (BOOSTED_TREE_CLASSIFIER), `ML.EVALUATE`, `ML.PREDICT`  
Dataset: `sing1261.ali1_predictive`

### Decisiones que aporta el modelo
- **Alerta temprana de reposición**: identifica qué producto-almacén entrará en quiebre el mes siguiente, con tiempo para emitir orden de compra
- **Priorización logística**: la probabilidad predicha (`predicted_flag_quiebre`) permite rankear las alertas de mayor a menor urgencia
- **Diferenciación regional**: el modelo captura que Oriente y Norte tienen mayor riesgo de quiebre que Centro (fricción logística)
- **Detección de patrones recurrentes**: `quiebres_ultimos_3_meses` permite identificar productos crónicamente problemáticos que requieren cambio de política de stock mínimo

---

## Arquitectura del pipeline

```
GCS bucket (ali1_bucket)
    │
    ▼
ali1_raw      ← etl_raw.sql      (tablas externas + ingesta incremental)
    │
    ▼
ali1_trusted  ← etl_trusted.sql  (limpieza, deduplicación, flags de calidad)
    │
    ▼
ali1_curated  ← etl_curated.sql  (modelo estrella: 7 dims + 4 facts)
    │
    ▼
ali1_predictive ← etl_predictive.sql
    ├── ARIMA_PLUS          → pred_ventas_forecast (90 días)
    └── BOOSTED_TREE_CLASSIFIER → pred_quiebre_stock (scoring completo)
```

Todos los procedimientos son autocontenidos, idempotentes y con tabla de control por capa (`etl_control`).
