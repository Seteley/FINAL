# Proyecto Ali1 — Pipeline de Datos y Modelos Predictivos

**Proyecto GCP**: `sing1261`  
**Empresa**: Alicorp  
**Última ejecución**: 2026-06-20

---

## Descripción general

Pipeline de datos de extremo a extremo implementado en Google Cloud Platform para Alicorp. Ingiere datos transaccionales y maestros desde GCS, los transforma a través de cuatro capas (Raw → Trusted → Curated → Predictive) y entrena dos modelos de Machine Learning en BigQuery ML: pronóstico de ventas por canal (ARIMA_PLUS) y predicción de quiebre de stock (BOOSTED_TREE_CLASSIFIER).

---

## Arquitectura

```
Data_origen/ (CSVs locales)
    │
    ▼
GCS Bucket: ali1_bucket
    │
    ▼
ali1_raw        ← tablas externas + ingesta incremental por partición de fecha
    │
    ▼
ali1_trusted    ← limpieza, deduplicación, flags de calidad
    │
    ▼
ali1_curated    ← modelo estrella: 7 dimensiones + 4 tablas de hechos
    │
    ▼
ali1_predictive ← entrenamiento ML + predicciones
    ├── ARIMA_PLUS               → pred_ventas_forecast (90 días × 6 canales)
    └── BOOSTED_TREE_CLASSIFIER  → pred_quiebre_stock (scoring completo)
```

Todos los ETL son **idempotentes** y registran cada operación en su tabla `etl_control` con estado `EXITOSO`/`ERROR`, conteo de filas y timestamp.

---

## Fuentes de datos

### Transaccionales (particionadas por fecha en GCS)
| Nombre lógico | Archivo CSV |
|---|---|
| ventas | `ventas_alicorp.csv` |
| pedidos | `pedidos_alicorp.csv` |
| devoluciones | `devoluciones_alicorp.csv` |
| fill_rate | `fill_rate_despachos.csv` |
| inventario | `inventario_alicorp.csv` |
| metas | `metas_comerciales_raw.csv` |
| promociones | `promociones_alicorp.csv` |
| inversion_promocional | `inversion_promocional_soles.csv` |

### Maestros (snapshot único)
| Nombre lógico | Archivo CSV |
|---|---|
| clientes | `clientes_alicorp.csv` |
| productos | `productos_alicorp.csv` |
| canal | `canal.csv` |
| geografia | `geografia.csv` |
| almacen | `almacen.csv` |
| vendedor | `vendedor.csv` |

---

## Estructura del repositorio

```
FINAL/
├── Data_origen/                    # CSVs fuente locales
│   ├── ventas_alicorp.csv
│   ├── pedidos_alicorp.csv
│   ├── devoluciones_alicorp.csv
│   ├── fill_rate_despachos.csv
│   ├── inventario_alicorp.csv
│   ├── metas_comerciales_raw.csv
│   ├── metas_operativas_raw.csv
│   ├── promociones_alicorp.csv
│   ├── inversion_promocional_soles.csv
│   ├── clientes_alicorp.csv
│   ├── productos_alicorp.csv
│   ├── canal.csv
│   ├── geografia.csv
│   ├── almacen.csv
│   └── vendedor.csv
│
├── create_datasets.py              # Crea los 4 datasets en BigQuery
├── create_folders_bucket.py        # Crea carpetas base en el bucket GCS
├── create_folders_bucket.ps1       # Equivalente PowerShell
├── create_raw_folders.py           # Crea subcarpetas raw/ por fuente
├── delete_keep_files.py            # Limpia archivos .keep del bucket
│
├── etl_raw.py                      # Ingesta incremental Python → ali1_raw
├── etl_raw.sql                     # Stored procedure sp_etl_raw
├── etl_trusted.sql                 # Stored procedure sp_etl_trusted
├── etl_curated.sql                 # Stored procedure sp_etl_curated
├── etl_predictive.sql              # Stored procedure sp_etl_predictive (ML)
├── etl_create_control_table.py     # Crea tabla de control manualmente
│
├── run_etl.py                      # Ejecuta solo ETL Raw
├── run_etl_curated.py              # Ejecuta solo ETL Curated
├── run_etl_trusted.py              # Ejecuta solo ETL Trusted
├── run_etl_predictive.py           # Ejecuta solo ETL Predictive (ML)
├── run_all.py                      # Ejecuta el pipeline completo de inicio a fin
│
├── create_datasets.py              # Setup inicial de datasets
├── documentacion_modelos.md        # Documentación detallada de modelos ML
├── README.md                       # Este archivo
│
└── dashboard/                      # Aplicación Streamlit
    ├── app.py                      # Punto de entrada: layout, tabs y filtros globales
    ├── paginas/
    │   ├── comercial.py            # Tab Gestión Comercial (KPIs + 5 gráficas)
    │   └── inventario.py           # Tab Gestión Operativa (KPIs + 7 gráficas)
    └── utils/
        └── bigquery.py             # Consultas BigQuery cacheadas (TTL 1h)
```

---

## Configuración inicial

### Prerrequisitos
- Python 3.10+
- Cuenta de servicio GCP con permisos sobre BigQuery y GCS en el proyecto `sing1261`
- Variable de entorno `GOOGLE_APPLICATION_CREDENTIALS` apuntando al JSON de la cuenta de servicio

### Instalación de dependencias
```bash
pip install google-cloud-bigquery google-cloud-storage
```

### Setup del entorno GCP (solo primera vez)

**1. Crear los datasets en BigQuery:**
```bash
python create_datasets.py
```

**2. Crear las carpetas base en el bucket GCS:**
```bash
python create_folders_bucket.py
```

**3. Crear las subcarpetas raw/ por fuente de datos:**
```bash
python create_raw_folders.py
```

**4. Subir los CSVs a GCS** en la estructura correcta:
```
ali1_bucket/
├── raw/ventas/20251231/ventas_alicorp.csv
├── raw/pedidos/20251231/pedidos_alicorp.csv
├── raw/clientes/clientes_alicorp.csv   ← maestros sin subcarpeta de fecha
└── ...
```

---

## Ejecución del pipeline

### Pipeline completo (recomendado)
Borra y recrea todos los datasets, luego ejecuta los 4 ETL en secuencia:
```bash
python run_all.py
```

### Ejecución por capa (para re-runs parciales)
```bash
python run_etl.py            # Solo capa Raw
python run_etl_trusted.py    # Solo capa Trusted
python run_etl_curated.py    # Solo capa Curated
python run_etl_predictive.py # Solo capa Predictive (entrena modelos ML)
```

### Ingesta incremental Python
El script `etl_raw.py` implementa ingesta incremental: detecta qué particiones de fecha ya fueron procesadas exitosamente (consultando `etl_control`) y omite las que ya existen.
```bash
python etl_raw.py
```

---

## Capas del pipeline

### ali1_raw — Capa de ingesta
- **Tablas externas** (`ext_*`): apuntan directamente a los CSV en GCS con wildcard `*/`
- **Tablas nativas**: cargadas incrementalmente por partición de fecha (`YYYYMMDD`)
- **Maestros**: carga snapshot completo con `WRITE_TRUNCATE`, añade columna `fecha_snapshot`
- **Tabla de control**: `etl_control` registra cada operación con estado y conteo de filas

### ali1_trusted — Capa de limpieza
- Elimina duplicados SAP (registros con sufijo `_DUP` en `id_linea_venta`)
- Aplica reglas de calidad por tabla (tipos de datos, rangos válidos)
- Tablas particionadas por fecha para performance en consultas
- Cada tabla registra su carga en `etl_control`

### ali1_curated — Modelo estrella
- **7 dimensiones**: `DIM_TIEMPO` (con feriados Perú), `DIM_CLIENTE`, `DIM_PRODUCTO`, `DIM_CANAL`, `DIM_GEOGRAFIA`, `DIM_ALMACEN`, `DIM_VENDEDOR`
- **4 tablas de hechos**: ventas, pedidos, inventario, metas
- `DIM_TIEMPO` cubre 2023-01-01 → 2025-12-31 con flags de feriado peruano

### ali1_predictive — Modelos ML
Ver sección **Modelos predictivos** abajo.

---

## Modelos predictivos

### Modelo 1: Pronóstico de Ventas por Canal

**Objetivo**: predecir ventas netas diarias (S/.) por canal para los próximos 90 días.  
**Algoritmo**: ARIMA_PLUS (BigQuery ML) con `auto_arima=TRUE`  
**Período histórico**: 2023-01-01 → 2025-12-31 (6,576 observaciones: 1,096 días × 6 canales)

**Resultados del modelo (parámetros por canal):**
| Canal | p (AR) | d | q (MA) | AIC | Error típico (S/.) |
|---|---|---|---|---|---|
| 5 | 1 | 1 | 1 | 25,253.77 | 24,479 |
| 3 | 0 | 1 | 1 | 25,266.88 | 24,686 |
| 1 | 0 | 1 | 1 | 25,412.42 | 26,343 |
| 6 | 0 | 1 | 1 | 25,476.27 | 27,123 |
| 2 | 1 | 1 | 1 | 25,789.59 | 31,367 |
| 4 | 1 | 1 | 1 | 25,863.18 | 32,338 |

**Forecast enero–marzo 2026:**
| Canal | Venta diaria media (S/.) | IC 90% (±S/.) |
|---|---|---|
| 1 | 127,594 | ±43,304 |
| 2 | 139,649 | ±57,241 |
| 3 | 121,802 | ±40,675 |
| 4 | 128,381 | ±53,658 |
| 5 | 127,155 | ±40,320 |
| 6 | 138,451 | ±44,585 |

**Tablas generadas**: `eval_ventas_forecast`, `explain_ventas_forecast`, `pred_ventas_forecast`

---

### Modelo 2: Predicción de Quiebre de Stock

**Objetivo**: predecir si un producto en un almacén entrará en quiebre de stock en el siguiente período (alerta temprana de reposición).  
**Algoritmo**: BOOSTED_TREE_CLASSIFIER (BigQuery ML, gradient boosting)  
**Split temporal**: 2023–2024 = TRAIN (25,846 filas) / 2025 = EVAL holdout (13,464 filas)

**Variables explicativas** (todas del período anterior T-1 para evitar data leakage):
| Variable | Descripción |
|---|---|
| `stock_mes_anterior` | Unidades disponibles en snapshot T-1 |
| `reservado_mes_anterior` | Unidades reservadas en T-1 |
| `cobertura_mes_anterior` | Días de cobertura calculados en T-1 |
| `demanda_mes_anterior` | Demanda diaria promedio del período anterior |
| `tendencia_stock` | Variación de stock entre T-1 y T-2 |
| `quiebres_ultimos_3_meses` | Número de quiebres en los 3 períodos previos |
| `categoria`, `linea_negocio` | Clasificación del producto |
| `tipo_almacen`, `macroregion` | Atributos del almacén |
| `mes`, `trimestre` | Estacionalidad |

**Métricas sobre holdout 2025:**
| Métrica | Valor |
|---|---|
| Precision | 54.28% |
| Recall | 99.91% |
| F1-Score | 70.34% |
| ROC-AUC | 98.53% |
| Accuracy | 95.46% |

> El recall cercano al 100% es el comportamiento correcto para alertas de inventario: es preferible revisar una falsa alarma que sufrir un stock-out. El ROC-AUC de 98.5% confirma excelente capacidad de discriminación al ajustar el umbral de decisión.

**Tablas generadas**: `train_quiebre_stock`, `eval_quiebre_stock`, `pred_quiebre_stock`

---

## Tabla de control (etl_control)

Cada capa tiene su propia tabla `etl_control` con el esquema:

| Columna | Tipo | Descripción |
|---|---|---|
| `tabla_destino` | STRING | Nombre de la tabla cargada |
| `archivo_origen` | STRING | URI GCS del archivo fuente |
| `fecha_particion` | DATE | Fecha de la partición procesada (null para maestros) |
| `tipo` | STRING | `INCREMENTAL`, `SNAPSHOT` o `FULL_REFRESH` |
| `estado` | STRING | `EXITOSO` o `ERROR` |
| `registros_cargados` | INT64 | Filas insertadas |
| `mensaje_error` | STRING | Detalle del error (si aplica) |
| `fecha_carga` | TIMESTAMP | Timestamp UTC de la carga |

Para consultar el estado del pipeline:
```sql
SELECT * FROM `sing1261.ali1_raw.etl_control` ORDER BY fecha_carga DESC LIMIT 50;
SELECT * FROM `sing1261.ali1_trusted.etl_control` ORDER BY fecha_carga DESC;
SELECT * FROM `sing1261.ali1_curated.etl_control` ORDER BY fecha_carga DESC;
```

---

## Dashboard — Alicorp Analytics

Aplicación web interactiva construida con **Streamlit** y **Plotly** que consume los cubos de BigQuery en tiempo real.

### Estructura del dashboard

```
dashboard/
├── app.py                  # Punto de entrada: configuración, tabs y filtros globales
├── paginas/
│   ├── comercial.py        # Tab "Gestión Comercial"
│   └── inventario.py       # Tab "Gestión Operativa"
└── utils/
    └── bigquery.py         # Funciones de consulta (cacheadas 1 hora con @st.cache_data)
```

### Cómo ejecutar

```bash
cd dashboard
streamlit run app.py
```

El dashboard se abre en `http://localhost:8501`.

### Fuentes de datos del dashboard

| Función | Tabla BigQuery | TTL caché |
|---|---|---|
| `get_comercial()` | `sing1261.ali1_kpi.CUBO_COMERCIAL` | 1 hora |
| `get_facturas()` | `sing1261.ali1_kpi.CUBO_FACTURAS` | 1 hora |
| `get_inventario()` | `sing1261.ali1_kpi.CUBO_INVENTARIO` | 1 hora |
| `get_frecuencia_compra()` | `sing1261.ali1_curated.FACT_VENTAS` | 1 hora |

### Tab 1 — Gestión Comercial

**Filtros disponibles**: Periodo, Canal, Marca, Región, Segmento (todos multiselect)

**KPIs con semáforo (verde/amarillo/rojo vs meta):**
| KPI | Descripción |
|---|---|
| KPI-01 Ventas Netas | Suma de ventas netas en S/ |
| KPI-02 Utilidad Bruta | Suma del margen bruto en S/ |
| KPI-03 Margen % | Margen bruto / Ventas netas |
| KPI-04 Cantidad Vendida | Unidades vendidas totales |
| KPI-05 Ticket Promedio | Ventas netas / Número de facturas |
| KPI-08 Frecuencia de Compra | Facturas / clientes únicos (consulta en vivo) |
| KPI-11 ROI Promocional | (Margen bruto − Inversión promo) / Inversión promo |
| KPI Tasa Devolución | Unidades devueltas / Cantidad vendida |

**Visualizaciones:**
| Gráfica | Tipo | Descripción |
|---|---|---|
| KPI-06 Participación de Canal x Ventas | Barras apiladas | Ventas netas por canal y periodo |
| Ventas Netas por Región | Mapa de burbujas (Plotly Mapbox) | Ventas por departamento del Perú |
| KPI-10 Productos por Ventas | Tabla interactiva | Ranking de SKUs por ventas, cantidad y margen |
| Ventas Netas por Línea de Negocio | Dona | Participación de cada línea de negocio |
| Ventas Netas YTD por Mes y Año | Línea | Comparativo de ventas mensuales por año (2023/2024/2025) |

### Tab 2 — Gestión Operativa

**Filtros disponibles**: Periodo, Almacén, Categoría (todos multiselect)

**KPIs con semáforo:**
| KPI | Descripción |
|---|---|
| KPI Tasa Quiebre | SKUs en quiebre / Total SKUs % |
| KPI Días Cobertura | Stock disponible / Demanda diaria |
| Stock Disponible Total | Unidades en stock |
| SKUs en Quiebre | Cantidad de SKUs sin stock |

**Visualizaciones:**
| Gráfica | Tipo | Descripción |
|---|---|---|
| Tasa Quiebre vs Meta | Gauge (velocímetro) | Semáforo visual vs la meta definida |
| Tasa Quiebre % vs Meta por Almacén | Barras + línea | Quiebre real vs meta por cada almacén |
| Stock Disponible Total por Almacén | Treemap | Jerarquía almacén → categoría con intensidad de color |
| Días Cobertura por Almacén | Barras horizontales + diamante meta | Cobertura actual vs objetivo por almacén |
| Tasa Quiebre % y Meta por Año y Mes | Área + línea | Evolución temporal del quiebre vs meta |
| Días Cobertura y Meta por Año y Mes | Área + línea | Evolución temporal de la cobertura vs meta |
| Almacenes por Categoría y Tasa de Quiebre % | Tabla pivot | Cruce categoría × almacén con tasa % |

### Dependencias del dashboard

```bash
pip install streamlit plotly pandas google-cloud-bigquery
```

---

## Servicios GCP utilizados

| Servicio | Uso |
|---|---|
| **Cloud Storage (GCS)** | Almacenamiento de archivos CSV fuente (`ali1_bucket`) |
| **BigQuery** | Data warehouse: datasets Raw, Trusted, Curated, Predictive |
| **BigQuery ML** | Entrenamiento y scoring de modelos ARIMA_PLUS y BOOSTED_TREE_CLASSIFIER |

---

## Decisiones de negocio que aportan los modelos

**Pronóstico de ventas:**
- Definir cuotas y presupuestos por canal con intervalo de confianza al 90%
- Identificar canales con cambios bruscos (6 y 4) que requieren revisión de causas externas
- Priorizar inversión comercial: canal 2 (S/. 139,649/día) vs canal 3 (S/. 121,802/día)

**Quiebre de stock:**
- Emitir órdenes de reposición antes de que ocurra la rotura de stock
- Rankear alertas por probabilidad predicha para asignar recursos de seguimiento
- Identificar productos crónicamente problemáticos (`quiebres_ultimos_3_meses`)
- Ajustar el umbral de decisión según la capacidad operativa vs. tolerancia al riesgo
