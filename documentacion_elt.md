# Documentación ELT — Carga y Transformación

## Arquitectura general

El pipeline sigue el patrón **ELT** sobre Google Cloud. Los datos crudos se depositan en Cloud Storage y se cargan sin modificar a BigQuery, donde ocurren todas las transformaciones mediante Stored Procedures en SQL. Los scripts Python actúan únicamente como orquestadores.

```
GCS (ali1_bucket/raw/)
        │
        ▼
  [L] ali1_raw          ← carga directa, sin transformación
        │
        ▼
  [T] ali1_trusted      ← limpieza y estandarización
        │
        ▼
  [T] ali1_curated      ← modelado dimensional (DIMs + FACTs)
        │
        ▼
  [T] ali1_kpi          ← cubos OLAP pre-agregados (tablas regulares via SP)
```

---

## 1. Carga — Capa RAW

### Descripción

Ingesta los archivos CSV desde Cloud Storage hacia BigQuery sin aplicar transformaciones de negocio. El proceso distingue dos tipos de tabla:

- **Transaccionales** (ventas, pedidos, devoluciones, fill_rate, inventario, metas, promociones, inversion_promocional, metas_operativas): carga incremental por partición de fecha. Cada archivo vive en una subcarpeta con formato `YYYYMMDD/`. El proceso extrae esa fecha del nombre del archivo (`_FILE_NAME`) y la registra como columna `fecha_carga`. Si una partición ya fue procesada exitosamente (consultado en `etl_control`), se omite — garantizando idempotencia.

- **Maestros** (clientes, productos, canal, geografia, almacen, vendedor): snapshot completo con `CREATE OR REPLACE TABLE`. En cada ejecución se reemplaza la tabla entera y se añade una columna `fecha_snapshot` con el timestamp de carga.

El proceso crea tablas externas temporales (`ext_*`) apuntando a GCS para la lectura, y las elimina al finalizar.

Cada operación registra su resultado (éxito, registros cargados, o mensaje de error) en `ali1_raw.etl_control`.

### Servicio cloud usado

| Servicio | Rol |
|---|---|
| **Cloud Storage** (`ali1_bucket`) | Fuente de los archivos CSV |
| **BigQuery** (`ali1_raw`) | Destino de la carga |

### Entrada

| Tabla / Archivo | Tipo | Ruta en GCS |
|---|---|---|
| ventas_alicorp.csv | Transaccional | `raw/ventas/YYYYMMDD/` |
| pedidos_alicorp.csv | Transaccional | `raw/pedidos/YYYYMMDD/` |
| devoluciones_alicorp.csv | Transaccional | `raw/devoluciones/YYYYMMDD/` |
| fill_rate_despachos.csv | Transaccional | `raw/fill_rate/YYYYMMDD/` |
| inventario_alicorp.csv | Transaccional | `raw/inventario/YYYYMMDD/` |
| metas_comerciales_raw.csv | Transaccional | `raw/metas/YYYYMMDD/` |
| promociones_alicorp.csv | Transaccional | `raw/promociones/YYYYMMDD/` |
| inversion_promocional_soles.csv | Transaccional | `raw/inversion_promocional/YYYYMMDD/` |
| metas_operativas_raw.csv | Transaccional | `raw/metas_operativas/YYYYMMDD/` |
| clientes_alicorp.csv | Maestro | `raw/clientes/` |
| productos_alicorp.csv | Maestro | `raw/productos/` |
| canal.csv | Maestro | `raw/canal/` |
| geografia.csv | Maestro | `raw/geografia/` |
| almacen.csv | Maestro | `raw/almacen/` |
| vendedor.csv | Maestro | `raw/vendedor/` |

### Salida

Tablas en el dataset `sing1261.ali1_raw`:

| Tabla | Tipo de carga | Particionada por |
|---|---|---|
| `ventas` | Incremental | `fecha_carga` |
| `pedidos` | Incremental | `fecha_carga` |
| `devoluciones` | Incremental | `fecha_carga` |
| `fill_rate` | Incremental | `fecha_carga` |
| `inventario` | Incremental | `fecha_carga` |
| `metas` | Incremental | `fecha_carga` |
| `promociones` | Incremental | `fecha_carga` |
| `inversion_promocional` | Incremental | `fecha_carga` |
| `metas_operativas` | Incremental | `fecha_carga` |
| `clientes` | Snapshot completo | — |
| `productos` | Snapshot completo | — |
| `canal` | Snapshot completo | — |
| `geografia` | Snapshot completo | — |
| `almacen` | Snapshot completo | — |
| `vendedor` | Snapshot completo | — |
| `etl_control` | Log de auditoría | — |

---

## 2. Transformación — Capa TRUSTED

### Descripción

Aplica reglas de calidad y limpieza sobre las tablas de `ali1_raw`. Todas las tablas se regeneran completas en cada ejecución (`FULL_REFRESH`). Las transformaciones por tabla son:

**ventas**
- Elimina registros con `estado_linea = 'DUPLICADO'` (duplicados generados por SAP).
- Limpia el sufijo `_DUP` del campo `id_linea_venta` usando `REGEXP_REPLACE`.
- Renombra `fecha_carga` a `fecha_carga_raw` para trazabilidad.

**pedidos**
- Pass-through: se traslada sin cambios, solo renombrando `fecha_carga` a `fecha_carga_raw`.

**fill_rate**
- Imputa valores nulos en `transportista` y `motivo_rechazo` con el literal `'No especificado'` mediante `COALESCE`.

**inventario**
- Elimina registros con `stock_disponible < 0` (stock negativo no conciliado).

**devoluciones**
- Pass-through: se traslada sin cambios, solo renombrando `fecha_carga` a `fecha_carga_raw`.

**metas**
- Filtra únicamente las filas con `es_version_aprobada = 1`, descartando versiones de planificación no vigentes.

**promociones**
- Aplica `TRIM` sobre `id_promocion_sap` para eliminar espacios.
- Agrega columna `flag_sap_id_pendiente` (1 si el ID está nulo o vacío, 0 si existe).

**inversion_promocional**
- Pass-through: se traslada sin cambios.

**clientes**
- Agrega columna `flag_direccion_completa` (1 si `direccion_fiscal` no es nulo, 0 si es nulo).

**productos**
- Limpia el sufijo `_DUP` del campo `cod_sap` usando `REGEXP_REPLACE`.

**metas_operativas**
- Filtra únicamente las filas con `es_version_aprobada = 1`.

**canal, geografia, almacen, vendedor**
- Pass-through: se trasladan sin cambios.

Cada operación registra su resultado en `ali1_trusted.etl_control`.

### Servicio cloud usado

| Servicio | Rol |
|---|---|
| **BigQuery** (`ali1_raw`) | Fuente de datos |
| **BigQuery** (`ali1_trusted`) | Destino de la transformación |

### Entrada

Todas las tablas del dataset `sing1261.ali1_raw`:
`ventas`, `pedidos`, `devoluciones`, `fill_rate`, `inventario`, `metas`, `promociones`, `inversion_promocional`, `metas_operativas`, `clientes`, `productos`, `canal`, `geografia`, `almacen`, `vendedor`.

### Salida

Tablas en el dataset `sing1261.ali1_trusted`:

| Tabla | Transformación aplicada |
|---|---|
| `ventas` | Sin duplicados SAP, `id_linea_venta` limpio |
| `pedidos` | Pass-through |
| `devoluciones` | Pass-through |
| `fill_rate` | NULLs imputados en transportista y motivo_rechazo |
| `inventario` | Sin stock negativo |
| `metas` | Solo versiones aprobadas |
| `promociones` | `id_promocion_sap` sin espacios + flag de pendiente |
| `inversion_promocional` | Pass-through |
| `clientes` | Con `flag_direccion_completa` |
| `productos` | `cod_sap` sin sufijo `_DUP` |
| `metas_operativas` | Solo versiones aprobadas |
| `canal` | Pass-through |
| `geografia` | Pass-through |
| `almacen` | Pass-through |
| `vendedor` | Pass-through |
| `etl_control` | Log de auditoría |

---

## 3. Transformación — Capa CURATED

### Descripción

Construye el modelo dimensional (esquema estrella) a partir de las tablas limpias de `ali1_trusted`. Genera dimensiones y tablas de hechos listas para consumo analítico. Todas las tablas se regeneran completas en cada ejecución (`FULL_REFRESH`).

**DIM_TIEMPO**
- Generada sintéticamente con `GENERATE_DATE_ARRAY` para el rango 2023-01-01 a 2025-12-31.
- Incluye atributos de fecha: año, trimestre, mes, nombre del mes, semana, día, nombre del día, semestre, label de semana.
- Agrega flags calculados: `es_fin_semana`, `es_feriado`, `es_dia_habil`.
- Incorpora feriados oficiales del Perú para los años 2023, 2024 y 2025 (hardcodeados).
- Clave primaria: `id_fecha` en formato entero `YYYYMMDD`.

**DIM_CANAL**
- Selección de columnas relevantes desde `trusted.canal`: `id_canal`, `cod_canal`, `nombre_canal`, `tipo_canal`, `margen_objetivo_pct`.

**DIM_GEOGRAFIA**
- Selección de columnas desde `trusted.geografia`: jerarquía geográfica completa (país, macroregión, departamento, provincia, ciudad, distrito, tipo de zona, ubigeo).

**DIM_ALMACEN**
- Selección de columnas desde `trusted.almacen`: identificadores, nombre, tipo, ubicación geográfica y estado.

**DIM_VENDEDOR**
- Selección de columnas desde `trusted.vendedor`: identificadores, nombre, cargo, zona asignada, fecha de ingreso y estado.

**DIM_CLIENTE**
- Deriva `id_cliente` como entero extrayendo la parte numérica de `id_cliente_raw` con `REGEXP_EXTRACT`.
- Agrega `fecha_primer_compra` mediante `LEFT JOIN` con `trusted.ventas` y `MIN(fecha_emision)`.

**DIM_PRODUCTO**
- Deriva `id_producto` como entero extrayendo la parte numérica de `id_producto_raw` con `REGEXP_EXTRACT`.
- Selecciona atributos comerciales: SKU, marca, categoría, subcategoría, línea de negocio, unidad de medida, precio lista y costo estándar.

**FACT_VENTAS**
- Une `trusted.ventas` con `trusted.devoluciones` (agrupadas por factura y producto) mediante `LEFT JOIN`.
- Imputa `unidades_devueltas` y `monto_devuelto_soles` con `COALESCE(..., 0)` cuando no hay devolución asociada.
- Genera `id_venta` con `ROW_NUMBER()`.
- Convierte `fecha_emision` al formato entero `YYYYMMDD` para enlazar con `DIM_TIEMPO`.

**FACT_INVENTARIO**
- Convierte `fecha_snapshot` al formato entero `YYYYMMDD` para enlazar con `DIM_TIEMPO`.
- Selecciona métricas de inventario: stock disponible, stock reservado, demanda diaria promedio, flag de quiebre y días de cobertura.
- Genera `id_inventario` con `ROW_NUMBER()`.

**FACT_METAS_COMERCIAL**
- Deriva `id_meta` como entero desde `id_meta_raw`.
- Convierte `(anio, mes)` a `id_fecha` en formato entero `YYYYMMDD` apuntando al primer día del mes.
- Incluye todas las métricas de meta comercial: ventas netas, margen bruto, cantidad, ticket promedio, frecuencia de compra, ROI promocional y tasa de devolución.

**FACT_METAS_OPERATIVO**
- Convierte `(anio, mes)` a `id_fecha` en formato entero `YYYYMMDD`.
- Incluye métricas operativas por almacén: meta de quiebre, días de cobertura, OTIF y fill rate.
- Genera `id_meta_op` con `ROW_NUMBER()`.

Cada operación registra su resultado en `ali1_curated.etl_control`.

### Servicio cloud usado

| Servicio | Rol |
|---|---|
| **BigQuery** (`ali1_trusted`) | Fuente de datos |
| **BigQuery** (`ali1_curated`) | Destino del modelo dimensional |

### Entrada

Tablas del dataset `sing1261.ali1_trusted`:
`ventas`, `pedidos`, `devoluciones`, `fill_rate`, `inventario`, `metas`, `metas_operativas`, `clientes`, `productos`, `canal`, `geografia`, `almacen`, `vendedor`.

### Salida

Tablas en el dataset `sing1261.ali1_curated`:

| Tabla | Tipo | Descripción |
|---|---|---|
| `DIM_TIEMPO` | Dimensión | Calendario 2023-2025 con feriados peruanos |
| `DIM_CANAL` | Dimensión | Canales de venta |
| `DIM_GEOGRAFIA` | Dimensión | Jerarquía geográfica |
| `DIM_ALMACEN` | Dimensión | Almacenes y su ubicación |
| `DIM_VENDEDOR` | Dimensión | Fuerza de ventas |
| `DIM_CLIENTE` | Dimensión | Clientes con fecha de primera compra |
| `DIM_PRODUCTO` | Dimensión | Catálogo de productos |
| `FACT_VENTAS` | Hecho | Ventas con devoluciones imputadas |
| `FACT_INVENTARIO` | Hecho | Snapshots de stock por producto y almacén |
| `FACT_METAS_COMERCIAL` | Hecho | Metas comerciales por canal y periodo |
| `FACT_METAS_OPERATIVO` | Hecho | Metas operativas por almacén y periodo |
| `etl_control` | Log | Log de auditoría de la capa curated |

---

## 4. Transformación — Capa KPI

### Descripción

Construye los tres cubos OLAP sobre la capa `ali1_curated`. Cada cubo es una **tabla regular** creada con `CREATE OR REPLACE TABLE` dentro del Stored Procedure `sp_etl_kpi()`. La carga es siempre FULL_REFRESH: la tabla se recrea completa en cada ejecución.

Se eligió el enfoque de tabla regular (en lugar de Materialized Views) porque BigQuery impone restricciones sobre las MVs que impedían implementar los cubos de forma completa y homogénea:

| Restricción de Materialized View | Cubo afectado | Solución con tabla |
|---|---|---|
| `COUNT(DISTINCT)` no soportado | CUBO_FACTURAS_TBL | `COUNT(DISTINCT num_factura)` y `COUNT(DISTINCT id_cliente)` disponibles |
| Expresiones que combinan varias agregaciones no soportadas | CUBO_INVENTARIO_TBL | `tasa_quiebre_pct` y `dias_cobertura` se calculan directamente en SQL |

Cada cubo se envuelve en un bloque `BEGIN / EXCEPTION WHEN ERROR THEN / END`, de modo que un fallo en un cubo no interrumpe los siguientes y el error queda registrado en `etl_control`.

**CUBO_COMERCIAL_TBL**
- Une `FACT_VENTAS` con `DIM_TIEMPO`, `DIM_CANAL`, `DIM_GEOGRAFIA`, `DIM_PRODUCTO`, `DIM_VENDEDOR` y `FACT_METAS_COMERCIAL`.
- Granularidad: Día × Canal × Departamento × SKU × Vendedor.
- Agrega métricas de ventas (`SUM`), márgenes y metas comerciales (`MAX` por canal × periodo).

**CUBO_FACTURAS_TBL**
- Une `FACT_VENTAS` con `DIM_TIEMPO`, `DIM_CANAL`, `DIM_GEOGRAFIA` y `DIM_VENDEDOR`. Sin dimensión Producto para evitar doble conteo de facturas y clientes.
- Granularidad: Día × Canal × Departamento × Vendedor.
- Incluye `COUNT(DISTINCT num_factura)` y `COUNT(DISTINCT id_cliente)` para métricas de ticket promedio y frecuencia de compra.

**CUBO_INVENTARIO_TBL**
- Une `FACT_INVENTARIO` con `DIM_TIEMPO`, `DIM_ALMACEN`, `DIM_PRODUCTO` y `FACT_METAS_OPERATIVO`.
- Granularidad: Mes × Almacén × SKU (los snapshots de inventario son mensuales).
- Pre-calcula en SQL `tasa_quiebre_pct = SUM(CASE WHEN stock<=0 THEN 1 ELSE 0 END) / COUNT(*) * 100` y `dias_cobertura = SUM(stock) / NULLIF(SUM(demanda), 0)`.

Cada operación registra su resultado en `sing1261.ali1_kpi.etl_control`.

### Servicio cloud usado

| Servicio | Rol |
|---|---|
| **BigQuery** (`ali1_curated`) | Fuente de datos (FACT + DIM) |
| **BigQuery** (`ali1_kpi`) | Destino de los cubos |

### Entrada

Tablas del dataset `sing1261.ali1_curated`:
`FACT_VENTAS`, `FACT_INVENTARIO`, `FACT_METAS_COMERCIAL`, `FACT_METAS_OPERATIVO`, `DIM_TIEMPO`, `DIM_CANAL`, `DIM_GEOGRAFIA`, `DIM_PRODUCTO`, `DIM_VENDEDOR`, `DIM_ALMACEN`.

### Salida

Tablas en el dataset `sing1261.ali1_kpi`:

| Tabla | Filas | Descripción |
|---|---|---|
| `CUBO_COMERCIAL_TBL` | ~500,000 | Métricas de ventas, margen, devoluciones y metas comerciales |
| `CUBO_FACTURAS_TBL` | ~172,000 | Facturas y clientes únicos para ticket promedio y frecuencia de compra |
| `CUBO_INVENTARIO_TBL` | ~40,000 | Stock, quiebre, cobertura y metas operativas |
| `etl_control` | — | Log de auditoría de la capa KPI |
