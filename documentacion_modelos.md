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
| `id_canal` | Identificador del canal de venta (1–6) |
| `ventas_netas_soles` | Valor histórico de la serie (la serie es el propio input del modelo) |

El modelo ARIMA_PLUS extrae automáticamente la estructura interna de la serie: tendencia, estacionalidad, autocorrelación y outliers. No requiere variables externas adicionales.

**Tabla de entrenamiento**: `ali1_predictive.train_ventas_forecast`  
**Período histórico**: 2023-01-01 → 2025-12-31 (1,096 días × 6 canales = 6,576 observaciones)

### Algoritmo
**ARIMA_PLUS** — BigQuery ML  
Modelo autorregresivo integrado de media móvil con componentes adicionales (detección automática de outliers, cambios de nivel y estacionalidad). Parámetros seleccionados automáticamente por `auto_arima=TRUE` por cada serie.

| Canal | p (AR) | d (diferenciación) | q (MA) | AIC | Error típico (S/.) | Outliers | Cambios de nivel |
|---|---|---|---|---|---|---|---|
| 5 | 1 | 1 | 1 | 25,253.77 ✓ | 24,479 | No | No |
| 3 | 0 | 1 | 1 | 25,266.88 | 24,686 | No | No |
| 1 | 0 | 1 | 1 | 25,412.42 | 26,343 | Sí | No |
| 6 | 0 | 1 | 1 | 25,476.27 | 27,123 | Sí | Sí |
| 2 | 1 | 1 | 1 | 25,789.59 | 31,367 | No | No |
| 4 | 1 | 1 | 1 | 25,863.18 | 32,338 | Sí | Sí |

`d=1` en todos los canales confirma que la serie tiene tendencia (requiere diferenciación de primer orden). La presencia de `p > 0` y `q > 0` indica estructura autoregresiva y de media móvil real — el modelo captura dependencias entre períodos consecutivos.

### Métricas de evaluación
| Métrica | Qué mide | Interpretación |
|---|---|---|
| **AIC** | Calidad de ajuste penalizando complejidad | Más bajo = mejor. Rango: 25,254–25,863 |
| **Error típico (√varianza)** | Desviación estándar de los residuos del modelo | Rango: S/. 24,479–32,338 por día |
| `has_spikes_and_dips` | Detección de valores atípicos significativos | Canales 1, 4 y 6 presentan outliers |
| `has_step_changes` | Detección de cambios bruscos de nivel en la serie | Canales 4 y 6 tuvieron saltos estructurales |

### Resultado
**Tablas generadas**:
- `eval_ventas_forecast` — 6 filas (1 por canal) con parámetros y métricas de ajuste
- `explain_ventas_forecast` — descomposición histórica + forecast (tendencia, estacionalidades, residuos)
- `pred_ventas_forecast` — 540 filas (90 días × 6 canales), enero–marzo 2026

**Forecast enero–marzo 2026**:
| Canal | Venta diaria media forecast (S/.) | Intervalo de confianza 90% (±S/.) |
|---|---|---|
| 1 | 127,594 | ±43,304 |
| 2 | 139,649 | ±57,241 |
| 3 | 121,802 | ±40,675 |
| 4 | 128,381 | ±53,658 |
| 5 | 127,155 | ±40,320 |
| 6 | 138,451 | ±44,585 |

Canal 2 y Canal 6 proyectan las ventas más altas del trimestre. Canal 3 y Canal 5 presentan los intervalos de confianza más estrechos, indicando mayor estabilidad en sus series históricas.

### Servicio cloud usado
**BigQuery ML** (Google Cloud Platform)  
Funciones: `CREATE MODEL` (ARIMA_PLUS), `ML.ARIMA_EVALUATE`, `ML.EXPLAIN_FORECAST`, `ML.FORECAST`  
Dataset: `sing1261.ali1_predictive`

### Decisiones que aporta el modelo
- **Planificación comercial**: metas de venta por canal para el trimestre siguiente con intervalo de confianza al 90%, útil para definir cuotas y presupuestos
- **Detección de anomalías**: identifica canales con cambios bruscos (6 y 4) o valores atípicos (1, 4, 6) que requieren revisión de causas externas
- **Priorización de recursos**: canal 2 (S/. 139,649/día) vs canal 3 (S/. 121,802/día) orienta dónde concentrar inversión comercial
- **Alerta de tendencia**: `d=1` en todos los canales confirma crecimiento sostenido; la proyección incorpora esta tendencia de forma automática

---

## Modelo 2: Predicción de Quiebre de Stock

### Objetivo del modelo
Predecir si un producto en un almacén determinado entrará en quiebre de stock en el siguiente período, usando exclusivamente información del período anterior (sin data leakage). El objetivo es activar alertas de reposición antes de que ocurra la rotura.

### Variable objetivo
`flag_quiebre` — variable binaria (0 = sin quiebre, 1 = quiebre en el período)

### Variables explicativas
| Variable | Descripción | Período |
|---|---|---|
| `stock_mes_anterior` | Unidades disponibles en el snapshot anterior | T-1 |
| `reservado_mes_anterior` | Unidades reservadas en el snapshot anterior | T-1 |
| `cobertura_mes_anterior` | Días de cobertura calculados en el snapshot anterior | T-1 |
| `demanda_mes_anterior` | Demanda diaria promedio del período anterior | T-1 |
| `tendencia_stock` | Variación de stock entre T-1 y T-2 (positivo = reposición, negativo = consumo) | T-1 vs T-2 |
| `quiebres_ultimos_3_meses` | Número de quiebres en los 3 períodos previos | Histórico |
| `categoria` | Categoría del producto | Estático |
| `linea_negocio` | Línea de negocio | Estático |
| `tipo_almacen` | Tipo de almacén (central, regional, etc.) | Estático |
| `macroregion` | Macroregión geográfica del almacén | Estático |
| `mes` | Mes del año (captura estacionalidad) | Contextual |
| `trimestre` | Trimestre Q1/Q2/Q3/Q4 | Contextual |

> **Nota sobre leakage corregido**: las variables `stock_disponible` y `dias_cobertura` del mismo período fueron excluidas porque están matemáticamente ligadas al label (stock=0 implica quiebre). El modelo usa exclusivamente información del período anterior para simular una predicción real de alerta temprana.

**Tabla de entrenamiento**: `ali1_predictive.train_quiebre_stock`  
**Split temporal**: 2023–2024 = TRAIN (25,846 filas, 65.7%) / 2025 = EVAL holdout (13,464 filas, 34.3%)

### Algoritmo
**BOOSTED_TREE_CLASSIFIER** — BigQuery ML  
Árbol de decisión potenciado por gradiente (Gradient Boosting). Configuración:
- `auto_class_weights = TRUE` — corrige el desbalance de clases entre quiebres y no-quiebres
- `num_parallel_tree = 4` — ensemble de 4 árboles paralelos por iteración
- `max_iterations = 100` — iteraciones de boosting
- `enable_global_explain = TRUE` — importancia de variables habilitada
- `data_split_method = 'CUSTOM'` — split temporal 2023-2024/2025 (más realista que split aleatorio)

### Métricas de evaluación
Evaluadas sobre el **holdout 2025** (datos no vistos en entrenamiento, 13,464 registros):

| Métrica | Valor | Qué mide |
|---|---|---|
| **Precision** | 54.28% | De cada 100 alertas de quiebre emitidas, 54.3 son quiebres reales (45.7% son falsas alarmas) |
| **Recall** | 99.91% | De cada 100 quiebres reales, el modelo detecta 99.9 — prácticamente ninguno se escapa |
| **F1-Score** | 70.34% | Balance harmónico entre precision y recall |
| **ROC-AUC** | 98.53% | Excelente capacidad de discriminación entre clases (1.0 = perfecto) |
| **Accuracy** | 95.46% | Porcentaje total de predicciones correctas (limitado por desbalance de clases) |

> **Interpretación del trade-off Precision/Recall con la nueva data**: con los CSV de inventario actualizados, la distribución de quiebres cambió, resultando en mayor volumen de alertas (recall cercano al 100%) a costa de más falsas alarmas (precision 54%). El modelo casi no pierde quiebres reales — para operaciones de inventario esto es el comportamiento correcto: es preferible revisar una alerta falsa que sufrir un stock-out. El ROC-AUC de 98.5% confirma que el modelo discrimina correctamente entre clases cuando se ajusta el umbral de decisión.

> **Nota sobre accuracy**: el 95.46% de accuracy no refleja el rendimiento en quiebres porque la mayoría de registros son de no-quiebre. Las métricas relevantes para este caso son precision, recall y ROC-AUC.

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
- **Alerta temprana de reposición**: identifica qué combinación producto-almacén entrará en quiebre el mes siguiente, con tiempo suficiente para emitir una orden de compra
- **Priorización logística**: la probabilidad predicha (`predicted_flag_quiebre`) permite rankear alertas de mayor a menor urgencia y asignar recursos de seguimiento
- **Diferenciación regional**: el modelo captura diferencias por macroregión y tipo de almacén que reflejan distintos niveles de fricción logística
- **Detección de patrones recurrentes**: `quiebres_ultimos_3_meses` identifica productos crónicamente problemáticos que requieren revisión de política de stock mínimo o acuerdo de nivel de servicio con proveedor
- **Ajuste de umbral de decisión**: con ROC-AUC de 98.5%, el negocio puede elegir el umbral de probabilidad que equilibre la capacidad operativa de atender alertas vs. la tolerancia al riesgo de stock-out

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
    ├── ARIMA_PLUS (bloques 1-5)          → pred_ventas_forecast (90 días)
    └── BOOSTED_TREE_CLASSIFIER (bloques 6-9) → pred_quiebre_stock (scoring completo)
```

Todos los procedimientos son autocontenidos, idempotentes y registran cada operación en su tabla de control `etl_control` con estado EXITOSO/ERROR, conteo de filas y timestamp.
