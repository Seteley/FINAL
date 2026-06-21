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
   `FACT_VENTAS`, controlando exactamente qué se suma — no la pre-agregación multidimensional
   de los cubos.
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

## Modelo 2 v2: Segmentación de Productos (KMEANS)

### Por qué se reemplazó el clasificador de quiebre de v1
El modelo de quiebre de v1 reportaba ROC-AUC 98.5%, pero ese resultado venía **casi por
completo de un leakage**: la feature `tendencia_stock` usaba el stock del propio período
objetivo, y como el quiebre se define justo como "stock ≤ 0", el modelo leía la respuesta.
Al corregir el leakage (features solo de información pasada), el desempeño cae a
**ROC-AUC ≈ 0.47 — equivalente a azar**. Se diagnosticó que en este dataset (sintético) los
eventos de riesgo **no tienen señal predecible**:

| Target de riesgo evaluado | Resultado |
|---|---|
| Quiebre próximo período (sin leakage) | ROC-AUC ~0.47 (azar) |
| Devolución de venta | ~3% uniforme en todos los canales y categorías |
| Bajo margen | margen ~22.5% constante (descuento ≈ 0 en toda la data) |
| Churn de cliente | inviable: los 300 clientes están activos los 36 meses |

En cambio, los **productos sí tienen estructura real** (precio 0.8–185, margen 17.9–42.5%,
rotación muy variable), por lo que se optó por una **segmentación descriptiva con K-MEANS**,
que no depende de poder predictivo y aporta valor de portafolio (tipo ABC).

### Objetivo
Agrupar los 78 SKU en segmentos homogéneos por comportamiento comercial, para decisiones de
portafolio: priorización, pricing, foco de surtido y políticas por tipo de producto.

### Features (estandarizadas, `standardize_features = TRUE`)
`precio_lista_soles`, `margen_pct`, `unidades_vendidas` (rotación),
`ventas_netas` (monetary), `tasa_devolucion_pct`.

### Algoritmo
`CREATE MODEL ... OPTIONS(model_type='KMEANS', num_clusters=4, standardize_features=TRUE)`.
La estandarización es clave porque las features están en escalas muy distintas (soles vs %).

### Métricas del clustering
| Métrica | Valor | Interpretación |
|---|---|---|
| Davies-Bouldin index | 1.585 | Menor = clusters más separados/compactos |
| Mean squared distance | 2.969 | Distancia media intra-cluster (espacio estandarizado) |

### Segmentos resultantes (78 SKU)
| Cluster | SKUs | Precio prom | Margen prom | Ventas prom | Perfil |
|---|---|---|---|---|---|
| 1 | 23 | S/ 11.6 | 34.0% | S/ 18.6M | Commodity estrella: bajo precio, alto margen, alto volumen |
| 2 | 41 | S/ 12.1 | 28.6% | S/ 3.7M | Cola larga: bajo aporte de ventas |
| 3 | 4 | S/ 156.5 | 21.8% | S/ 4.6M | Premium nicho: precio muy alto, margen bajo |
| 4 | 10 | S/ 79.5 | 24.7% | S/ 15.9M | Premium de volumen: precio alto y ventas altas |

### Decisiones que aporta
- **Portafolio ABC**: distingue los SKU commodity estrella (cluster 1) del resto.
- **Foco comercial**: el cluster 2 (41 SKU de bajo aporte) es candidato a racionalización.
- **Pricing/margen**: el cluster 3 (premium nicho, margen bajo) merece revisión de precio.

### Tablas generadas
`train_segmentacion_productos_v2`, `model_segmentacion_productos_v2`,
`eval_segmentacion_productos_v2`, `pred_segmentacion_productos_v2` (cada SKU con su `cluster`).

---

## Equivalencia v1 ↔ v2

| Concepto | v1 | v2 |
|---|---|---|
| Procedimiento | `sp_etl_predictive` | `sp_etl_predictive_v2` |
| Script SQL | `etl_predictive.sql` | `etl_predictive_v2.sql` |
| Runner Python | `run_etl_predictive.py` | `run_etl_predictive_v2.py` |
| Forecast — algoritmo | ARIMA_PLUS | ARIMA_PLUS_XREG (+ regresores) |
| Forecast — tablas | `*_ventas_forecast` | `*_ventas_forecast_v2` (+ `future_regressors_v2`) |
| 2.º modelo — tipo | Clasificación de quiebre (BOOSTED_TREE) | Segmentación de productos (KMEANS) |
| 2.º modelo — motivo | — | Riesgo sin señal en estos datos → se pivota a clustering descriptivo |
| 2.º modelo — tablas | `*_quiebre_stock` | `*_segmentacion_productos_v2` |

Ambas versiones coexisten en `sing1261.ali1_predictive` y registran su ejecución en la misma
tabla de control `etl_control`.

### Cómo ejecutar
```bash
python run_etl_predictive_v2.py
```

---

## Servicio cloud usado
**BigQuery ML** (Google Cloud Platform)
Funciones: `CREATE MODEL` (ARIMA_PLUS_XREG / KMEANS),
`ML.ARIMA_EVALUATE`, `ML.FORECAST` (con regresores futuros), `ML.EVALUATE`, `ML.PREDICT`.
Dataset: `sing1261.ali1_predictive`.
