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

1. **Grano atómico.** Los cubos de `kpi` vienen pre-agregados; el forecast necesita la serie
   diaria por canal y la segmentación necesita los agregados por SKU del grano de
   `FACT_VENTAS`, controlando exactamente qué se suma.
2. **Sin sesgo de muestra.** `CUBO_COMERCIAL_TBL` hace `INNER JOIN` con
   `FACT_METAS_COMERCIAL` y descarta filas sin meta — entrenar sobre eso sesgaría el modelo.
3. **Semántica limpia.** Los cubos mezclan medidas aditivas (`SUM`) con no aditivas (`MAX`
   de metas); como fuente de features eso es impuro.

---

## Modelo 1 v2: Pronóstico de Ventas por Canal

### Objetivo del modelo

Predecir las **ventas netas diarias (S/.) por canal de distribución** para los próximos 90 días
(Q1-2026), incorporando el efecto de feriados nacionales e inversión promocional planificada.
El pronóstico permite anticipar picos y valles de demanda por canal para optimizar el plan
comercial y logístico.

### Variable objetivo

`ventas_netas_soles` — suma diaria de ventas netas en soles, segmentada por `id_canal`.

**Tabla de entrenamiento**: `train_ventas_forecast_v2`
(6,576 filas = 1,096 días × 6 canales; período 2023-2025)

### Variables explicativas

El modelo combina la **propia serie temporal** (componentes autoregresivos ARIMA) con dos
**regresores externos**:

| Variable | Fuente | Descripción | Cobertura en entrenamiento |
|---|---|---|---|
| `es_feriado` | `DIM_TIEMPO.es_feriado` | 1 si el día es feriado en Perú, 0 si no | 36 feriados × 6 canales validados |
| `inversion_promo` | `FACT_VENTAS.inversion_promocional_soles` | Inversión promocional del día (S/.) | 0 % nulos, 0 % ceros, prom. S/ 2,028 |

Para el período de pronóstico (Q1-2026), los regresores futuros están en `future_regressors_v2`:
- `es_feriado`: determinista según calendario (en Q1-2026 solo el 1-ene).
- `inversion_promo`: supuesto de planificación = promedio histórico por `id_canal × mes` —
  funciona como **palanca what-if**: cambiar estos valores permite simular escenarios sin
  reentrenar.

**Cambio respecto a v1**: v1 usaba ARIMA_PLUS univariante (sin regresores externos). La adición
de `es_feriado` e `inversion_promo` explica varianza que la serie no capturaba por sí sola.

### Algoritmo

**BigQuery ML — ARIMA_PLUS_XREG** (ARIMA con regresores externos).

```sql
CREATE OR REPLACE MODEL `sing1261.ali1_predictive.model_ventas_forecast_v2`
OPTIONS(
    model_type             = 'ARIMA_PLUS_XREG',
    time_series_timestamp_col = 'ds',
    time_series_data_col   = 'ventas_netas_soles',
    time_series_id_col     = 'id_canal',
    horizon                = 90,
    auto_arima             = TRUE,
    data_frequency         = 'AUTO_FREQUENCY'
)
AS SELECT ds, id_canal, ventas_netas_soles, es_feriado, inversion_promo
   FROM `sing1261.ali1_predictive.train_ventas_forecast_v2`;
```

> **Nota técnica**: `decompose_time_series` no es compatible con ARIMA_PLUS_XREG y se omite
> (verificado: produce error si se incluye). `auto_arima=TRUE` selecciona automáticamente los
> órdenes p, d, q del modelo.

### Métricas de evaluación

Evaluado con `ML.ARIMA_EVALUATE` (tabla `eval_ventas_forecast_v2`). Métrica principal: **AIC**
(Akaike Information Criterion) — penaliza complejidad; **menor es mejor**.

| Canal | AIC v1 (ARIMA_PLUS) | AIC v2 (ARIMA_PLUS_XREG) | Mejora |
|---|---|---|---|
| 1 | 25,412.4 | 24,470.7 | −941.7 |
| 2 | 25,789.6 | 24,197.1 | −1,592.5 |
| 3 | 25,266.9 | 24,281.1 | −985.8 |
| 4 | 25,863.2 | 24,362.9 | −1,500.3 |
| 5 | 25,253.8 | 24,401.2 | −852.6 |
| 6 | 25,476.3 | 24,389.5 | −1,086.7 |

**Mejora consistente en los 6 canales** (entre 850 y 1,600 puntos de AIC). Los regresores
aportan información real.

Los intervalos de confianza al 90% se reducen **~40% frente a v1**:

| Canal | Venta diaria media (S/.) | IC 90% v2 (±S/.) | IC 90% v1 (ref.) |
|---|---|---|---|
| 1 | 117,861 | ±27,986 | ±43,304 |
| 2 | 109,793 | ±24,941 | ±57,241 |
| 3 | 109,622 | ±25,667 | ±40,675 |
| 4 | 112,392 | ±26,642 | ±53,658 |
| 5 | 113,301 | ±27,301 | ±40,320 |
| 6 | 120,364 | ±26,984 | ±44,585 |

### Servicio cloud

**Google Cloud Platform — BigQuery ML**

| Función | Uso |
|---|---|
| `CREATE MODEL` (ARIMA_PLUS_XREG) | Entrenamiento del modelo serie temporal con regresores |
| `ML.ARIMA_EVALUATE` | Extracción de métricas AIC, AICC, BIC, varianza |
| `ML.FORECAST` | Generación del pronóstico 90 días con banda IC 90% |

Dataset: `sing1261.ali1_predictive`
Tablas: `train_ventas_forecast_v2`, `future_regressors_v2`, `model_ventas_forecast_v2`,
`eval_ventas_forecast_v2`, `pred_ventas_forecast_v2`.

### Decisiones que aporta el modelo

| Decisión | Cómo usa el pronóstico |
|---|---|
| **Planificación de despacho** | Anticipar picos de demanda diaria por canal para asignar capacidad logística |
| **Metas comerciales Q1** | Baseline objetivo por canal: la banda IC 90% define el rango de variabilidad esperado |
| **Simulación de inversión promocional** | Modificar `inversion_promo` en `future_regressors_v2` y re-ejecutar `ML.FORECAST` sin reentrenar — estima el impacto de una campaña |
| **Gestión de feriados** | El modelo descuenta automáticamente la caída de ventas en feriados; ya no requiere ajuste manual en las metas |

---

## Modelo 2 v2: Segmentación de Productos (Portafolio)

### Objetivo del modelo

Agrupar los **78 SKU activos** en segmentos homogéneos según su comportamiento comercial
(precio, margen, rotación, aporte en ventas, devolución). El resultado permite tomar decisiones
de portafolio: priorización de surtido, pricing, racionalización y foco de acciones comerciales
por tipo de producto (equivalente a un análisis ABC enriquecido).

### Variable objetivo

**No aplica** — KMEANS es un algoritmo de aprendizaje **no supervisado**: no existe una variable
a predecir. El modelo asigna cada SKU a un cluster minimizando la distancia intra-cluster en el
espacio de features estandarizado.

### Variables explicativas

Las features representan las cinco dimensiones del comportamiento de un SKU. Se estandarizan
(`standardize_features = TRUE`) porque están en escalas muy distintas (soles vs. porcentajes):

| Feature | Descripción | Rango aproximado |
|---|---|---|
| `precio_lista_soles` | Precio de lista del SKU (S/.) | 0.8 – 185.0 |
| `margen_pct` | Margen bruto sobre precio de venta (%) | 17.9 – 42.5 |
| `unidades_vendidas` | Volumen total vendido en el período (rotación) | Variable |
| `ventas_netas` | Ingresos netos acumulados por SKU (S/.) | Variable |
| `tasa_devolucion_pct` | Porcentaje de unidades devueltas sobre vendidas (%) | Variable |

Fuente: `FACT_VENTAS` JOIN `DIM_PRODUCTO` (grano `ali1_curated`), agregado a nivel SKU.
Tabla de entrenamiento: `train_segmentacion_productos_v2` (78 filas — un registro por SKU).

### Algoritmo

**BigQuery ML — KMEANS** con 4 clusters y estandarización de features.

```sql
CREATE OR REPLACE MODEL `sing1261.ali1_predictive.model_segmentacion_productos_v2`
OPTIONS(
    model_type          = 'KMEANS',
    num_clusters        = 4,
    standardize_features = TRUE
)
AS SELECT precio_lista_soles, margen_pct, unidades_vendidas,
          ventas_netas, tasa_devolucion_pct
   FROM `sing1261.ali1_predictive.train_segmentacion_productos_v2`;
```

La elección de `num_clusters = 4` se justifica por interpretabilidad de negocio: 4 segmentos
producen perfiles accionables (estrellas, cola larga, premium nicho, premium volumen) sin
fragmentación excesiva.

### Métricas de evaluación

Evaluado con `ML.EVALUATE` (tabla `eval_segmentacion_productos_v2`):

| Métrica | Valor | Interpretación |
|---|---|---|
| **Davies-Bouldin index** | 1.585 | Relación entre dispersión intra-cluster y separación entre clusters; **menor = mejor**. Valores < 2 se consideran aceptables. |
| **Mean squared distance** | 2.969 | Distancia cuadrática media de cada punto a su centroide (espacio estandarizado). |

No se utilizan métricas de clasificación (accuracy, ROC-AUC) porque el modelo es no supervisado.
No existe un "ground truth" de etiquetas contra el que comparar.

### Servicio cloud

**Google Cloud Platform — BigQuery ML**

| Función | Uso |
|---|---|
| `CREATE MODEL` (KMEANS) | Entrenamiento del clustering con estandarización automática |
| `ML.EVALUATE` | Extracción de Davies-Bouldin index y mean squared distance |
| `ML.PREDICT` | Asignación de cada SKU a su cluster + distancia al centroide |

Dataset: `sing1261.ali1_predictive`
Tablas: `train_segmentacion_productos_v2`, `model_segmentacion_productos_v2`,
`eval_segmentacion_productos_v2`, `pred_segmentacion_productos_v2`.

### Decisiones que aporta el modelo

| Cluster | Perfil | SKUs | Decisión de negocio |
|---|---|---|---|
| 1 — Commodity estrella | Precio bajo (~S/12), margen alto (34%), volumen muy alto | 23 | Proteger surtido, defender precio, máxima disponibilidad en stock |
| 2 — Cola larga | Precio bajo (~S/12), margen medio (29%), ventas bajas | 41 | Revisar rentabilidad; candidatos a racionalización de portafolio |
| 3 — Premium nicho | Precio muy alto (~S/157), margen bajo (22%), volumen bajo | 4 | Revisar pricing — el margen no justifica el posicionamiento premium; evaluar descontinuar |
| 4 — Premium volumen | Precio alto (~S/80), margen medio (25%), ventas altas | 10 | Reforzar distribución en canales modernos/exportación; potencial de crecimiento |

**Usos adicionales**:
- **Foco de surtido por canal**: cruzar el cluster del SKU con el canal de venta para identificar
  qué segmento lidera en cada canal.
- **Política diferenciada de descuentos**: el cluster 1 tolera menos descuento (margen ya alto);
  el cluster 4 puede absorberlo para ganar volumen.
- **Reentrenamiento periódico**: ejecutar `sp_etl_predictive_v2` trimestral o semestralmente
  para detectar migraciones de SKUs entre clusters (señal temprana de cambio de producto).

### Adicionales — Por qué se reemplazó el clasificador de quiebre (v1)

El modelo de quiebre de v1 reportaba **ROC-AUC 98.5%**, pero ese resultado venía casi por
completo de **data leakage**: la feature `tendencia_stock` usaba `stock(T) − stock(T-1)`,
donde `stock(T)` era contemporáneo con la etiqueta (quiebre se define como `stock ≤ 0`),
haciendo que el modelo leyera prácticamente la respuesta.

Adicionalmente, la evaluación de v1 corría `ML.EVALUATE` sobre toda la tabla de entrenamiento
(incluyendo el conjunto de holdout sin filtrar), lo que inflaba artificialmente las métricas.

Al corregir ambos problemas:
- `tendencia_stock` reformulado como `LAG(stock, T-1) − LAG(stock, T-2)` (info estrictamente pasada).
- `ML.EVALUATE` filtrado solo sobre `split = TRUE` (holdout 2025).

El desempeño cae a **ROC-AUC ≈ 0.47 — peor que azar**. Se diagnosticaron además otras cuatro
alternativas de clasificación, todas sin señal en este dataset:

| Target de riesgo evaluado | Resultado |
|---|---|
| Quiebre próximo período (sin leakage) | ROC-AUC ~0.47 (azar) |
| Devolución de venta | ~3 % uniforme en todos los canales y categorías |
| Bajo margen | Margen ~22.5 % constante (descuento ≈ 0 en toda la data) |
| Churn de cliente | Inviable: los 300 clientes están activos los 36 meses |

Los productos sí tienen estructura real (precio 0.8–185, margen 17.9–42.5 %, rotación muy
variable), por lo que se optó por la segmentación descriptiva con KMEANS, que no depende de
poder predictivo y aporta valor de portafolio inmediato.

---

## Equivalencia v1 ↔ v2

| Concepto | v1 | v2 |
|---|---|---|
| Procedimiento | `sp_etl_predictive` | `sp_etl_predictive_v2` |
| Script SQL | `etl_predictive.sql` | `etl_predictive_v2.sql` |
| Runner Python | `run_etl_predictive.py` | `run_etl_predictive_v2.py` |
| Forecast — algoritmo | ARIMA_PLUS | ARIMA_PLUS_XREG (+ regresores externos) |
| Forecast — tablas | `*_ventas_forecast` | `*_ventas_forecast_v2` + `future_regressors_v2` |
| 2.º modelo — tipo | Clasificación de quiebre (BOOSTED_TREE) | Segmentación de productos (KMEANS) |
| 2.º modelo — motivo | — | Riesgo sin señal en estos datos → clustering descriptivo |
| 2.º modelo — tablas | `*_quiebre_stock` | `*_segmentacion_productos_v2` |

Ambas versiones coexisten en `sing1261.ali1_predictive` y registran su ejecución en la misma
tabla de control `etl_control`.

### Cómo ejecutar

```bash
python run_etl_predictive_v2.py
```
