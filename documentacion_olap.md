# Documentación OLAP — Proyecto Ali1

**Dataset BigQuery**: `sing1261.ali1_kpi`  
**Proyecto GCP**: `sing1261`  
**Fecha**: 2026-06-20

---

## 1. ¿Qué es un cubo OLAP?

Un **cubo OLAP** (Online Analytical Processing) es una estructura de datos multidimensional diseñada para responder consultas analíticas de manera eficiente. A diferencia de las tablas relacionales —que almacenan datos en filas y columnas planas—, un cubo organiza los datos según **medidas** (qué se mide: ventas, stock, margen) y **dimensiones** (desde qué perspectiva se analiza: tiempo, producto, canal, geografía).

Las operaciones características de un cubo OLAP son:

| Operación | Descripción | Ejemplo en este proyecto |
|---|---|---|
| **Drill-down** | Ir de un nivel de granularidad alto a uno más fino | De Año → Mes → Semana → Día |
| **Roll-up** | Agregar de un nivel fino a uno más alto | De SKU → Subcategoría → Categoría → Línea de negocio |
| **Slice** | Filtrar por un valor de una dimensión | Solo canal "B2B Industrial" |
| **Dice** | Filtrar por múltiples dimensiones a la vez | Canal "B2B" + Año 2025 + Región "Lima" |
| **Pivot** | Rotar ejes del cubo para cambiar la perspectiva | Filas = Canales, Columnas = Meses |

---

## 2. Implementación en BigQuery

En este proyecto los tres cubos se implementan como **tablas regulares** (`CREATE OR REPLACE TABLE`) creadas por un **Stored Procedure** de BigQuery (`sp_etl_kpi`). Esto significa que BigQuery **pre-computa y almacena físicamente** el resultado de los JOINs y agregaciones sobre las tablas de la capa `ali1_curated`. Cada cubo se recarga ejecutando el SP, que se integra en el pipeline orquestado por `run_all.py`.

```
ali1_curated (tablas FACT + DIM)
    │
    ▼  sp_etl_kpi() — JOINs + GROUP BY + métricas calculadas
ali1_kpi (tablas regulares _TBL = cubos OLAP materializados)
    │
    ▼  SELECT + filtros en pandas
Dashboard Streamlit
```

### ¿Por qué tablas regulares y no Materialized Views?

BigQuery Materialized Views tienen restricciones de SQL que impidieron su uso homogéneo:

| Restricción MV | Cubo afectado | Solución con tabla regular |
|---|---|---|
| `COUNT(DISTINCT)` no permitido | CUBO_FACTURAS | `COUNT(DISTINCT num_factura)` y `COUNT(DISTINCT id_cliente)` ahora disponibles |
| Expresiones entre varias agregaciones no permitidas | CUBO_INVENTARIO | `tasa_quiebre_pct` y `dias_cobertura` calculadas directamente en SQL |
| CTEs no soportadas | Todos | Sin restricción de sintaxis dentro del SP |

Al usar tablas regulares vía SP, los tres cubos tienen **el mismo tipo de objeto**, las mismas capacidades SQL y el mismo patrón de carga (FULL_REFRESH), lo que los hace homogéneos.

### Orquestación del pipeline

```
run_all.py
  ├── ali1_raw        ← sp_etl_raw()        (ingesta de datos simulados)
  ├── ali1_trusted    ← sp_etl_trusted()     (limpieza y normalización)
  ├── ali1_curated    ← sp_etl_curated()     (modelo estrella: FACT + DIM)
  ├── ali1_kpi        ← sp_etl_kpi()         (cubos OLAP: _TBL × 3)
  └── ali1_predictive ← sp_etl_predictive()  (modelos ML sobre curated)
```

Para re-ejecutar solo los cubos sin correr todo el pipeline:

```bash
python run_etl_kpi.py
```

El resultado de cada carga se registra en `sing1261.ali1_kpi.etl_control` con estado, filas cargadas y timestamp.

---

## 3. Modelo estrella de la capa Curated

Antes de describir los cubos, es importante entender las tablas que los alimentan:

### Tablas de hechos

| Tabla | Descripción | Granularidad |
|---|---|---|
| `FACT_VENTAS` | Una fila por línea de venta (factura × SKU) | Transacción diaria |
| `FACT_INVENTARIO` | Snapshot mensual de stock por producto y almacén | Mes × Producto × Almacén |
| `FACT_METAS_COMERCIAL` | Metas comerciales por canal y mes | Mes × Canal |
| `FACT_METAS_OPERATIVO` | Metas operativas por almacén y mes | Mes × Almacén |

### Tablas de dimensiones

| Tabla | Descripción | Atributos clave |
|---|---|---|
| `DIM_TIEMPO` | Calendario 2023–2025 con feriados Perú | fecha, anio, trimestre, mes, semana, es_feriado, es_dia_habil |
| `DIM_PRODUCTO` | Catálogo de SKUs | cod_sku, nombre_sku, marca, categoria, subcategoria, linea_negocio |
| `DIM_CLIENTE` | Clientes con fecha de primera compra | cod_cliente, razon_social, ruc, segmento, credito_limite_soles |
| `DIM_CANAL` | Canales de distribución | nombre_canal, tipo_canal, margen_objetivo_pct |
| `DIM_GEOGRAFIA` | Geografía del Perú | macroregion, Departamento, provincia, ciudad, tipo_zona |
| `DIM_ALMACEN` | Almacenes y centros de distribución | nombre_almacen, tipo_almacen, macroregion, region, ciudad |
| `DIM_VENDEDOR` | Fuerza de ventas | nombre_completo, cargo, zona_asignada |

---

## 4. Descripción de los cubos

### 4.1 CUBO_COMERCIAL_TBL

**Objeto BigQuery**: `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`  
**Tipo**: `TABLE` (tabla regular, full refresh via SP)  
**Fuente principal**: `FACT_VENTAS` + `FACT_METAS_COMERCIAL`  
**Granularidad del resultado**: Día × Canal × Departamento × SKU × Vendedor  
**Filas cargadas**: ~500,000  
**Refresh**: al ejecutar `sp_etl_kpi()`

**Propósito**: Concentra todas las métricas de rendimiento comercial (ventas, margen, devoluciones, inversión promocional) junto con sus metas, permitiendo análisis de cumplimiento desde cualquier combinación de dimensiones.

---

#### 7.3. Cubo OLAP — CUBO_COMERCIAL_TBL

| Medida | Descripción | Tipo de agregación | Dimensiones de análisis | Jerarquía sugerida | Consulta o visual asociado |
|---|---|---|---|---|---|
| **Ventas Netas** (`ventas_netas`) | Ingresos por ventas después de descuentos, en soles | `SUM` | Tiempo, Canal, Geografía, Producto, Vendedor | Año → Semestre → Trimestre → Mes → Semana → Día | Gráfico de línea YTD comparando años; barras apiladas por canal y mes |
| **Venta Bruta** (`venta_bruta`) | Ingresos antes de descuentos, en soles | `SUM` | Tiempo, Canal, Geografía, Producto | Año → Trimestre → Mes | Comparativo venta bruta vs neta para medir impacto de descuentos |
| **Costo de Ventas** (`costo_ventas`) | Costo estándar de los productos vendidos, en soles | `SUM` | Tiempo, Canal, Producto | Año → Mes; Línea negocio → Categoría → SKU | Análisis de estructura de costos por categoría |
| **Margen Bruto** (`margen_bruto`) | Ventas netas − Costo de ventas, en soles | `SUM` | Tiempo, Canal, Producto, Geografía | Año → Mes; Categoría → Marca → SKU | Tabla de rentabilidad por SKU; gauge de cumplimiento vs meta |
| **Margen %** *(derivado)* | `margen_bruto / ventas_netas × 100` | Derivada en dashboard | Tiempo, Canal, Producto | Mes; Categoría | KPI card con semáforo vs meta de margen |
| **Inversión Promocional** (`inversion_promo`) | Gasto en actividades promocionales, en soles | `SUM` | Tiempo, Canal, Producto | Año → Mes; Canal → SKU | Barras comparativas inversión vs margen generado |
| **ROI Promocional %** *(derivado)* | `(margen_bruto − inversion_promo) / inversion_promo × 100` | Derivada en dashboard | Tiempo, Canal | Mes; Canal | KPI card; dispersión inversión vs retorno por canal |
| **Cantidad Vendida** (`cantidad_vendida`) | Unidades vendidas totales | `SUM` | Tiempo, Canal, Producto, Geografía, Vendedor | Año → Mes; Línea → Categoría → SKU | Ranking de productos; tendencia de volumen por mes |
| **Unidades Devueltas** (`unidades_devueltas`) | Unidades que regresaron por devolución | `SUM` | Tiempo, Canal, Producto | Mes; Categoría → SKU | Análisis de devoluciones por categoría; alerta de SKUs problemáticos |
| **Monto Devuelto** (`monto_devuelto`) | Valor monetario de devoluciones, en soles | `SUM` | Tiempo, Canal, Producto | Mes; Canal | Impacto financiero de devoluciones |
| **Tasa Devolución %** *(derivado)* | `unidades_devueltas / cantidad_vendida × 100` | Derivada en dashboard | Tiempo, Canal, Producto | Mes; Canal → SKU | KPI card con semáforo; mapa de calor canal × mes |
| **Meta Ventas Netas** (`meta_ventas_netas`) | Objetivo de ventas netas definido por el área comercial | `MAX` (por canal × mes) | Canal, Tiempo | Año → Mes; Canal | Comparativo real vs meta en barras o bullet chart |
| **Meta Margen Bruto S/** (`meta_margen_bruto`) | Objetivo de margen en soles | `MAX` | Canal, Tiempo | Mes; Canal | Gauge de cumplimiento de margen |
| **Meta Margen %** (`meta_margen_pct`) | Objetivo de porcentaje de margen | `MAX` | Canal, Tiempo | Mes | Semáforo en KPI card |
| **Meta Cantidad Vendida** (`meta_cantidad_vendida`) | Objetivo de unidades | `MAX` | Canal, Tiempo | Mes; Canal | Bullet chart unidades reales vs meta |
| **Meta Ticket Promedio** (`meta_ticket_promedio`) | Objetivo de valor promedio por factura | `MAX` | Canal, Tiempo | Mes | Comparativo ticket real vs meta |
| **Meta Frecuencia Compra** (`meta_frecuencia_compra`) | Objetivo de visitas promedio por cliente | `MAX` | Canal, Tiempo | Mes | KPI card frecuencia real vs meta |
| **Meta ROI Promocional %** (`meta_roi_pct`) | Objetivo de retorno sobre inversión promo | `MAX` | Canal, Tiempo | Mes | Semáforo ROI real vs meta |
| **Meta Tasa Devolución %** (`meta_tasa_devolucion`) | Límite máximo de devolución aceptable | `MAX` | Canal, Tiempo | Mes | Alerta cuando tasa real supera la meta |
| **% Cumplimiento Ventas** *(derivado)* | `ventas_netas / meta_ventas_netas × 100` | Derivada en dashboard | Canal, Tiempo | Mes; Canal | Barra de progreso por canal; semáforo global |

**Dimensiones y atributos disponibles en este cubo:**

| Dimensión | Atributos | Niveles de jerarquía |
|---|---|---|
| **Tiempo** | `anio`, `semestre`, `trimestre`, `mes`, `mes_nombre`, `anio_mes`, `semana_anio`, `semana_label`, `fecha`, `periodo` | Año → Semestre → Trimestre → Mes → Semana → Día |
| **Canal** | `nombre_canal`, `tipo_canal` | Tipo Canal → Canal |
| **Geografía** | `macroregion`, `Departamento`, `provincia`, `ciudad`, `tipo_zona` | Macroregión → Departamento → Provincia → Ciudad |
| **Producto** | `linea_negocio`, `categoria`, `subcategoria`, `marca`, `cod_sku`, `nombre_sku` | Línea Negocio → Categoría → Subcategoría → Marca → SKU |
| **Vendedor** | `nombre_vendedor`, `zona_asignada` | Zona → Vendedor |

---

### 4.2 CUBO_FACTURAS_TBL

**Objeto BigQuery**: `sing1261.ali1_kpi.CUBO_FACTURAS_TBL`  
**Tipo**: `TABLE` (tabla regular, full refresh via SP)  
**Fuente principal**: `FACT_VENTAS`  
**Granularidad del resultado**: Día × Canal × Departamento × Vendedor *(sin dimensión Producto)*  
**Filas cargadas**: ~172,000  
**Refresh**: al ejecutar `sp_etl_kpi()`

**Propósito**: Cubo especializado en métricas de comportamiento del cliente. Al excluir la dimensión Producto se evita inflar los conteos de facturas y clientes (una factura con 10 SKUs se contaría 10 veces si Producto estuviera en el GROUP BY). Es complementario a `CUBO_COMERCIAL_TBL`: mientras el comercial analiza qué se vende, este analiza cómo se compra.

> **Nota técnica**: `COUNT(DISTINCT)` está disponible en este cubo porque es una tabla regular. Esta operación no está soportada en BigQuery Materialized Views, razón por la cual se eligió el enfoque de tabla via SP para toda la capa KPI.

---

#### 7.3. Cubo OLAP — CUBO_FACTURAS_TBL

| Medida | Descripción | Tipo de agregación | Dimensiones de análisis | Jerarquía sugerida | Consulta o visual asociado |
|---|---|---|---|---|---|
| **Ventas Netas** (`ventas_netas`) | Ingresos por ventas en soles, sumados a nivel de factura | `SUM` | Tiempo, Canal, Geografía, Vendedor | Año → Mes; Canal | Base para calcular ticket promedio por cualquier corte dimensional |
| **Número de Facturas** (`num_facturas`) | Cantidad de transacciones únicas (facturas distintas) | `COUNT(DISTINCT num_factura)` | Tiempo, Canal, Geografía, Vendedor | Año → Mes; Canal → Vendedor | Volumen transaccional; tendencia de actividad comercial |
| **Clientes Activos** (`num_clientes_activos`) | Clientes que realizaron al menos una compra en el período | `COUNT(DISTINCT id_cliente)` | Tiempo, Canal, Geografía | Mes; Canal; Departamento | Penetración de mercado; evolución de base activa |
| **Ticket Promedio** *(derivado)* | `ventas_netas / num_facturas` | Derivada en dashboard | Tiempo, Canal, Geografía, Vendedor | Año → Mes; Canal | KPI card con semáforo vs meta; línea temporal por canal |
| **Frecuencia de Compra** *(derivado)* | `num_facturas / num_clientes_activos` | Derivada en dashboard | Tiempo, Canal | Mes; Canal | KPI card; barras comparativas por canal |

**Dimensiones y atributos disponibles en este cubo:**

| Dimensión | Atributos | Niveles de jerarquía |
|---|---|---|
| **Tiempo** | `anio`, `semestre`, `trimestre`, `mes`, `mes_nombre`, `anio_mes`, `semana_anio`, `semana_label`, `fecha`, `periodo` | Año → Semestre → Trimestre → Mes → Semana → Día |
| **Canal** | `nombre_canal`, `tipo_canal` | Tipo Canal → Canal |
| **Geografía** | `macroregion`, `Departamento`, `provincia`, `ciudad`, `tipo_zona` | Macroregión → Departamento → Provincia → Ciudad |
| **Vendedor** | `nombre_vendedor`, `zona_asignada` | Zona → Vendedor |

> **Nota**: La Frecuencia de Compra global (independiente de canal o región) se calcula con una consulta directa a `FACT_VENTAS` mediante la función `get_frecuencia_compra()` del dashboard, que aplica los mismos filtros activos del usuario.

---

### 4.3 CUBO_INVENTARIO_TBL

**Objeto BigQuery**: `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`  
**Tipo**: `TABLE` (tabla regular, full refresh via SP)  
**Fuente principal**: `FACT_INVENTARIO` + `FACT_METAS_OPERATIVO`  
**Granularidad del resultado**: Mes × Almacén × SKU  
**Filas cargadas**: ~40,000  
**Refresh**: al ejecutar `sp_etl_kpi()`  
**Nota**: Los snapshots de inventario son mensuales, por lo que la granularidad temporal es mensual aunque `DIM_TIEMPO` esté disponible a nivel diario.

**Propósito**: Monitoriza la salud del inventario en la red de almacenes: quiebres de stock, cobertura de días, y cumplimiento de metas operativas. Permite anticipar rupturas de stock a través del modelo de ML en `ali1_predictive`.

> **Nota técnica**: `tasa_quiebre_pct` y `dias_cobertura` se calculan directamente en SQL dentro del SP (`ROUND(SUM(...)/COUNT(*)*100, 2)` y `ROUND(SUM(stock)/NULLIF(SUM(demanda),0), 1)`). Esta sintaxis —combinar múltiples funciones de agregación en una expresión— no está soportada en BigQuery Materialized Views, y es otra razón clave para elegir tablas regulares.

---

#### 7.3. Cubo OLAP — CUBO_INVENTARIO_TBL

| Medida | Descripción | Tipo de agregación | Dimensiones de análisis | Jerarquía sugerida | Consulta o visual asociado |
|---|---|---|---|---|---|
| **Stock Disponible** (`stock_disponible`) | Unidades físicamente disponibles para despacho | `SUM` | Tiempo, Almacén, Producto | Mes; Macroregión → Almacén; Categoría → SKU | Treemap stock por almacén × categoría; evolución temporal por almacén |
| **Stock Reservado** (`stock_reservado`) | Unidades comprometidas en pedidos pendientes de despacho | `SUM` | Tiempo, Almacén, Producto | Mes; Almacén; Categoría | Barras apiladas disponible vs reservado por almacén |
| **SKUs en Quiebre** (`skus_en_quiebre`) | Cantidad de SKUs con stock disponible ≤ 0 | `SUM(CASE WHEN stock <= 0 THEN 1 ELSE 0)` | Tiempo, Almacén, Producto | Mes; Almacén; Categoría → SKU | Contador de alertas; ranking de SKUs crónicamente en quiebre |
| **Total SKUs** (`total_skus`) | Cantidad total de SKUs activos en el almacén en el período | `COUNT(*)` | Tiempo, Almacén, Producto | Mes; Almacén | Denominador para calcular tasa de quiebre |
| **Tasa de Quiebre %** (`tasa_quiebre_pct`) | `skus_en_quiebre / total_skus × 100`, redondeado a 2 decimales | Pre-calculada en SP | Tiempo, Almacén, Producto | Mes; Almacén; Categoría | Gauge vs meta; barras por almacén; serie temporal mensual |
| **Días de Cobertura** (`dias_cobertura`) | `stock_disponible / demanda_diaria_prom`, redondeado a 1 decimal | Pre-calculada en SP | Tiempo, Almacén, Producto | Mes; Almacén; Categoría | Barras horizontales por almacén vs meta; serie temporal |
| **Meta Quiebre %** (`meta_quiebre_pct`) | Límite máximo de tasa de quiebre definido por operaciones | `MAX` (por almacén × mes) | Almacén, Tiempo | Mes; Almacén | Línea de referencia en barras; umbral en gauge |
| **Meta Días Cobertura** (`meta_dias_cobertura`) | Objetivo mínimo de días de cobertura | `MAX` | Almacén, Tiempo | Mes; Almacén | Diamante de meta en barras horizontales; semáforo en KPI card |
| **Meta OTIF %** (`meta_otif_pct`) | Objetivo de On Time In Full (pedidos entregados completos y a tiempo) | `MAX` | Almacén, Tiempo | Mes; Almacén | KPI card; comparativo por almacén (disponible para uso futuro en dashboard) |
| **Meta Fill Rate %** (`meta_fill_rate_pct`) | Objetivo de porcentaje de órdenes atendidas sin quiebre | `MAX` | Almacén, Tiempo | Mes; Almacén | KPI card; disponible para extensión del dashboard operativo |
| **% Cumplimiento Quiebre** *(derivado)* | `tasa_quiebre_pct / meta_quiebre_pct × 100` (menor es mejor) | Derivada en dashboard | Almacén, Tiempo | Mes; Almacén | Semáforo invertido: verde cuando quiebre real < meta |
| **% Cumplimiento Cobertura** *(derivado)* | `dias_cobertura / meta_dias_cobertura × 100` | Derivada en dashboard | Almacén, Tiempo | Mes; Almacén | Semáforo: verde cuando cobertura real ≥ meta |

**Dimensiones y atributos disponibles en este cubo:**

| Dimensión | Atributos | Niveles de jerarquía |
|---|---|---|
| **Tiempo** | `anio`, `mes`, `mes_nombre`, `anio_mes`, `semana_anio`, `semana_label`, `fecha`, `periodo` | Año → Mes *(granularidad efectiva: mensual por ser snapshot)* |
| **Almacén** | `nombre_almacen`, `tipo_almacen`, `macroregion`, `region`, `ciudad` | Macroregión → Región → Ciudad → Almacén |
| **Producto** | `linea_negocio`, `categoria`, `subcategoria`, `marca`, `cod_sku`, `nombre_sku` | Línea Negocio → Categoría → Subcategoría → Marca → SKU |

---

## 5. Comparativo entre los tres cubos

| Característica | CUBO_COMERCIAL_TBL | CUBO_FACTURAS_TBL | CUBO_INVENTARIO_TBL |
|---|---|---|---|
| **Tipo BigQuery** | Tabla regular | Tabla regular | Tabla regular |
| **Creado por** | `sp_etl_kpi()` | `sp_etl_kpi()` | `sp_etl_kpi()` |
| **Modo de carga** | FULL_REFRESH | FULL_REFRESH | FULL_REFRESH |
| **Filas cargadas** | ~500,000 | ~172,000 | ~40,000 |
| **Tabla de hechos base** | FACT_VENTAS | FACT_VENTAS | FACT_INVENTARIO |
| **Metas incluidas** | Comerciales (canal × mes) | No | Operativas (almacén × mes) |
| **Dimensión Producto** | Sí | **No** (evita doble conteo) | Sí |
| **Dimensión Cliente** | No (solo id_cliente en FACT) | No | No |
| **Dimensión Almacén** | No | No | Sí |
| **COUNT(DISTINCT)** | No aplica | `num_facturas`, `num_clientes_activos` | No aplica |
| **Métricas pre-calculadas en SQL** | `margen_bruto` (SUM resta) | — | `tasa_quiebre_pct`, `dias_cobertura` |
| **KPIs exclusivos** | Ventas, margen, ROI, devoluciones | Ticket promedio, frecuencia compra | Stock, quiebre, cobertura, OTIF |

---

## 6. Jerarquías de dimensiones

### Dimensión Tiempo

```
Año
 └── Semestre (S1 / S2)
      └── Trimestre (Q1 / Q2 / Q3 / Q4)
           └── Mes (Enero … Diciembre)
                └── Semana (S01-2023 … S52-2025)
                     └── Día (fecha)
                          ├── es_fin_semana (0/1)
                          ├── es_feriado (0/1)
                          └── es_dia_habil (0/1)
```

### Dimensión Producto

```
Línea de Negocio
 └── Categoría
      └── Subcategoría
           └── Marca
                └── SKU (cod_sku / nombre_sku)
```

### Dimensión Geografía

```
Macroregión
 └── Departamento
      └── Provincia
           └── Ciudad
                └── Tipo Zona (urbana / rural)
```

### Dimensión Almacén

```
Macroregión
 └── Región
      └── Ciudad
           └── Tipo Almacén (central / regional / tránsito)
                └── Almacén (nombre_almacen)
```

### Dimensión Canal

```
Tipo Canal (moderno / tradicional / digital / institucional)
 └── Canal (B2B Industrial / Canal Moderno / Canal Tradicional / E-Commerce / Exportación / HoReCa)
```

---

## 7. Limitaciones conocidas

| Limitación | Cubo afectado | Explicación |
|---|---|---|
| Metas en granularidad canal + mes | CUBO_COMERCIAL_TBL | Las metas comerciales se definen por canal y mes, pero el cubo tiene granularidad más fina (+ producto + geo + vendedor). Esto genera filas duplicadas de metas que deben deduplicarse en el dashboard con `drop_duplicates(["nombre_canal", "periodo"])` antes de sumarlas. |
| Snapshots mensuales en inventario | CUBO_INVENTARIO_TBL | La fuente `FACT_INVENTARIO` tiene un registro por mes (no diario), por lo que los filtros por semana o día en este cubo no producen variaciones reales de inventario. |
| JOIN INNER con metas | CUBO_COMERCIAL_TBL, CUBO_INVENTARIO_TBL | Si un canal o almacén no tiene meta registrada para un período, las filas de ventas/inventario de ese período desaparecen del resultado. |
| Sin dimensión Cliente en los cubos | Todos | El análisis a nivel de cliente individual (RFM, CLV) requiere consultas directas a `FACT_VENTAS` + `DIM_CLIENTE`, no está disponible en los cubos. |
| Agregación de días de cobertura | CUBO_INVENTARIO_TBL | Para reagregar `dias_cobertura` a un nivel superior (p.ej. almacén total) no se puede sumar ni promediar directamente. Se debe recuperar la demanda como `stock / dias_cobertura`, sumar las demandas, y dividir el stock total entre la demanda total. El dashboard implementa esta lógica. |

---

## 8. Ejemplo de consultas SQL sobre los cubos

### Ventas netas y margen por canal en 2025

```sql
SELECT
  nombre_canal,
  SUM(ventas_netas)  AS ventas_netas_total,
  SUM(margen_bruto)  AS margen_bruto_total,
  ROUND(SUM(margen_bruto) / NULLIF(SUM(ventas_netas), 0) * 100, 2) AS margen_pct
FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`
WHERE anio = 2025
GROUP BY nombre_canal
ORDER BY ventas_netas_total DESC;
```

### Drill-down: ventas por mes dentro de una categoría

```sql
SELECT
  anio_mes,
  categoria,
  SUM(ventas_netas) AS ventas_netas
FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`
WHERE categoria = 'Aceites'
GROUP BY anio_mes, categoria
ORDER BY anio_mes;
```

### Tasa de quiebre por almacén en el último mes disponible

```sql
SELECT
  nombre_almacen,
  SUM(skus_en_quiebre)                                               AS skus_quiebre,
  SUM(total_skus)                                                    AS total_skus,
  ROUND(SUM(skus_en_quiebre) / NULLIF(SUM(total_skus), 0) * 100, 2) AS tasa_quiebre_pct,
  MAX(meta_quiebre_pct)                                              AS meta
FROM `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`
WHERE anio_mes = (SELECT MAX(anio_mes) FROM `sing1261.ali1_kpi.CUBO_INVENTARIO_TBL`)
GROUP BY nombre_almacen
ORDER BY tasa_quiebre_pct DESC;
```

### Ticket promedio por canal y mes

```sql
SELECT
  anio_mes,
  nombre_canal,
  SUM(ventas_netas)                                               AS ventas_netas,
  SUM(num_facturas)                                               AS facturas,
  ROUND(SUM(ventas_netas) / NULLIF(SUM(num_facturas), 0), 2)     AS ticket_promedio
FROM `sing1261.ali1_kpi.CUBO_FACTURAS_TBL`
WHERE anio = 2025
GROUP BY anio_mes, nombre_canal
ORDER BY anio_mes, nombre_canal;
```

### Cumplimiento de ventas vs meta por canal

```sql
SELECT
  nombre_canal,
  SUM(ventas_netas)                                                       AS ventas_reales,
  SUM(meta_ventas_netas)                                                  AS meta_ventas,
  ROUND(SUM(ventas_netas) / NULLIF(SUM(meta_ventas_netas), 0) * 100, 1)  AS cumplimiento_pct
FROM (
  -- Deduplicar metas antes de sumar (las metas se repiten por fila de producto/geo/vendedor)
  SELECT nombre_canal, periodo,
         SUM(ventas_netas)      AS ventas_netas,
         MAX(meta_ventas_netas) AS meta_ventas_netas
  FROM `sing1261.ali1_kpi.CUBO_COMERCIAL_TBL`
  WHERE anio = 2025
  GROUP BY nombre_canal, periodo
)
GROUP BY nombre_canal
ORDER BY cumplimiento_pct DESC;
```

### Verificar estado de la última carga KPI

```sql
SELECT tabla_destino, estado, registros_cargados, fecha_carga
FROM `sing1261.ali1_kpi.etl_control`
ORDER BY fecha_carga DESC
LIMIT 10;
```
