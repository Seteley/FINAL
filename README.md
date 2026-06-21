# Proyecto Ali1 — Pipeline de Datos y Modelos Predictivos

**Proyecto GCP**: `sing1261`  
**Empresa**: Alicorp  
**Última ejecución**: 2026-06-20

---

## Descripción general

Pipeline de datos de extremo a extremo implementado en Google Cloud Platform para Alicorp. Ingiere datos transaccionales y maestros desde GCS, los transforma a través de cinco capas (Raw → Trusted → Curated → KPI → Predictive) y entrena dos modelos de Machine Learning en BigQuery ML: pronóstico de ventas por canal (ARIMA_PLUS) y predicción de quiebre de stock (BOOSTED_TREE_CLASSIFIER). Sobre la capa Curated se construye una capa KPI con tres cubos analíticos OLAP implementados como **tablas regulares via Stored Procedure** en BigQuery, que sirven de fuente al dashboard Streamlit.

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
    ├──▶ ali1_kpi        ← cubos OLAP (tablas regulares via sp_etl_kpi)
    │        ├── CUBO_COMERCIAL_TBL  → ventas, margen, metas comerciales
    │        ├── CUBO_FACTURAS_TBL   → ticket promedio, frecuencia de compra
    │        └── CUBO_INVENTARIO_TBL → stock, quiebre, cobertura, metas operativas
    │
    └──▶ ali1_predictive ← entrenamiento ML + predicciones
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
├── sql/                            # Definición de los cubos analíticos (capa ali1_kpi)
│   ├── etl_kpi.sql                 # Stored procedure sp_etl_kpi — crea los 3 cubos _TBL
│   ├── cubo_comercial_mv.sql       # MV de referencia (superada por etl_kpi.sql)
│   ├── cubo_facturas_mv.sql        # MV de referencia (superada por etl_kpi.sql)
│   └── cubo_inventario_mv.sql      # MV de referencia (superada por etl_kpi.sql)
│
├── run_etl_kpi.py                  # Ejecuta solo ETL KPI (crea SP y llama CALL)
├── create_datasets.py              # Setup inicial de datasets
├── documentacion_modelos.md        # Documentación detallada de modelos ML
├── documentacion_elt.md            # Documentación del pipeline ELT por capa
├── documentacion_olap.md           # Documentación de los cubos OLAP
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
python run_etl_kpi.py        # Solo cubos KPI (CUBO_COMERCIAL_TBL, CUBO_FACTURAS_TBL, CUBO_INVENTARIO_TBL)
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

### ali1_kpi — Capa de cubos analíticos

Esta capa expone los datos de `ali1_curated` como **cubos OLAP listos para el dashboard**, pre-agregados por todas las dimensiones relevantes (tiempo, canal, geografía, producto, vendedor, almacén). Los tres cubos son **tablas regulares** creadas por el Stored Procedure `sp_etl_kpi()` con FULL_REFRESH.

#### ¿Por qué tablas regulares y no Materialized Views?

Las **Materialized Views** de BigQuery tienen restricciones de SQL que impedían implementar los cubos de forma completa:

| Restricción | Cubo afectado | Impacto |
|---|---|---|
| `COUNT(DISTINCT)` no soportado | CUBO_FACTURAS_TBL | No se podía contar facturas ni clientes únicos |
| Expresiones entre múltiples agregaciones no soportadas | CUBO_INVENTARIO_TBL | `tasa_quiebre_pct` y `dias_cobertura` no podían calcularse en SQL |

Las tablas regulares vía SP no tienen estas restricciones, son del mismo tipo, tienen el mismo patrón de carga y se integran naturalmente al pipeline existente. El resultado es equivalente al de las MVs en cuanto a pre-cómputo, pero sin limitaciones de SQL.

#### Cubos disponibles

| Cubo | Tipo BigQuery | Filas | Descripción |
|---|---|---|---|
| `CUBO_COMERCIAL_TBL` | Tabla regular | ~500,000 | Ventas, margen, devoluciones y metas comerciales |
| `CUBO_FACTURAS_TBL` | Tabla regular | ~172,000 | Facturas y clientes únicos para ticket promedio y frecuencia de compra |
| `CUBO_INVENTARIO_TBL` | Tabla regular | ~40,000 | Stock, quiebre (`tasa_quiebre_pct`), cobertura (`dias_cobertura`) y metas operativas |

#### Para recrear los cubos

```bash
python run_etl_kpi.py
```

El resultado de cada cubo queda registrado en `sing1261.ali1_kpi.etl_control`:

```sql
SELECT tabla_destino, estado, registros_cargados, fecha_carga
FROM `sing1261.ali1_kpi.etl_control`
ORDER BY fecha_carga DESC;
```

### ali1_predictive — Modelos ML
Ver sección **Modelos predictivos** abajo.

---

## Modelos predictivos

> **Versión v2 disponible.** Existe una iteración mejorada de ambos modelos que **convive**
> con la v1 (objetos con sufijo `_v2`, generados por `sp_etl_predictive_v2`):
> pronóstico con **ARIMA_PLUS_XREG** (regresores de feriado e inversión promocional, AIC
> mejorado en los 6 canales) y clasificador de quiebre con la **evaluación corregida** sobre
> el holdout 2025. Ver [documentacion_modelos_v2.md](documentacion_modelos_v2.md) y ejecutar
> con `python run_etl_predictive_v2.py`. La sección siguiente describe la v1 original.

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
SELECT * FROM `sing1261.ali1_kpi.etl_control` ORDER BY fecha_carga DESC;
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

| Función | Tabla BigQuery | Tipo | TTL caché |
|---|---|---|---|
| `get_comercial()` | `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL` | Tabla regular | 1 hora |
| `get_facturas()` | `sing1261.ali1_kpi.CUBO_FACTURAS_TBL` | Tabla regular | 1 hora |
| `get_inventario()` | `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL` | Tabla regular | 1 hora |
| `get_frecuencia_compra()` | `sing1261.ali1_curated.FACT_VENTAS` | Tabla física | Por combinación de filtros* |

> \* `get_frecuencia_compra()` requiere `COUNT(DISTINCT id_cliente)` sobre los registros filtrados, lo que no puede derivarse sumando columnas pre-agregadas. Se ejecuta una consulta a BigQuery por cada nueva combinación de filtros; combinaciones repetidas se sirven del caché.

El caché de Streamlit (`@st.cache_data(ttl=3600)`) almacena el DataFrame en memoria durante 1 hora. La primera carga descarga todos los datos; las interacciones posteriores (filtros, navegación) operan sobre el DataFrame en memoria sin nuevas consultas a BigQuery.

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
pip install streamlit plotly pandas google-cloud-bigquery google-cloud-bigquery-storage db-dtypes
```

- **`google-cloud-bigquery`**: cliente Python para ejecutar consultas y leer resultados.
- **`google-cloud-bigquery-storage`**: transfiere datos usando la BigQuery Storage API (formato Arrow columnar comprimido), lo que hace la descarga de grandes volúmenes ~10× más rápida que la API REST estándar. **Requerido** para que el dashboard cargue en segundos en lugar de minutos.
- **`db-dtypes`**: extensión de tipos de datos de BigQuery para pandas (DATE, TIME, NUMERIC). Requerido por el cliente BigQuery al convertir resultados a DataFrame.

---

## Servicios GCP utilizados

| Servicio | Uso |
|---|---|
| **Cloud Storage (GCS)** | Almacenamiento de archivos CSV fuente (`ali1_bucket`) |
| **BigQuery** | Data warehouse: datasets Raw, Trusted, Curated, KPI y Predictive |
| **BigQuery Stored Procedures** | Stored Procedure `sp_etl_kpi()` crea los tres cubos OLAP como tablas regulares con FULL_REFRESH |
| **BigQuery Storage API** | Transferencia rápida de datos al dashboard mediante protocolo Arrow columnar |
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
