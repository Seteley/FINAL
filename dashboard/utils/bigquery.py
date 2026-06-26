import streamlit as st
from google.cloud import bigquery
import pandas as pd

PROJECT = "sing1261"
CLIENT = bigquery.Client(project=PROJECT)


def _query(sql: str) -> pd.DataFrame:
    return CLIENT.query(sql).to_dataframe(create_bqstorage_client=False)


@st.cache_data(ttl=3600)
def get_comercial() -> pd.DataFrame:
    return _query(f"""
        SELECT *
        FROM `{PROJECT}.ali1_kpi.CUBO_COMERCIAL_TBL`
    """)


@st.cache_data(ttl=3600)
def get_facturas() -> pd.DataFrame:
    return _query(f"""
        SELECT *
        FROM `{PROJECT}.ali1_kpi.CUBO_FACTURAS_TBL`
    """)


@st.cache_data(ttl=3600)
def get_inventario() -> pd.DataFrame:
    return _query(f"""
        SELECT *
        FROM `{PROJECT}.ali1_kpi.CUBO_INVENTARIO_TBL`
    """)


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║ CAPA PREDICTIVA v2 — consultas para la pestaña "Predictiva" (removible)    ║
# ║ Para quitar la pestaña: elimina estas 4 funciones, el archivo             ║
# ║ paginas/predictiva.py y el bloque tab_pred en app.py.                      ║
# ╚══════════════════════════════════════════════════════════════════════════╝
@st.cache_data(ttl=3600)
def get_pred_ventas() -> pd.DataFrame:
    """Pronóstico de ventas por canal (ARIMA_PLUS_XREG), próximos 90 días."""
    return _query(f"""
        SELECT
            p.id_canal,
            c.nombre_canal,
            DATE(p.forecast_timestamp)             AS fecha,
            p.forecast_value                       AS venta_pronostico,
            p.prediction_interval_lower_bound      AS lim_inf,
            p.prediction_interval_upper_bound      AS lim_sup
        FROM `{PROJECT}.ali1_predictive.pred_ventas_forecast_v2` p
        JOIN `{PROJECT}.ali1_curated.DIM_CANAL` c ON p.id_canal = c.id_canal
        ORDER BY p.id_canal, fecha
    """)


@st.cache_data(ttl=3600)
def get_hist_ventas() -> pd.DataFrame:
    """Serie histórica diaria de ventas por canal (reutiliza la tabla de entrenamiento)."""
    return _query(f"""
        SELECT
            t.id_canal,
            c.nombre_canal,
            t.ds                  AS fecha,
            t.ventas_netas_soles
        FROM `{PROJECT}.ali1_predictive.train_ventas_forecast_v2` t
        JOIN `{PROJECT}.ali1_curated.DIM_CANAL` c ON t.id_canal = c.id_canal
        ORDER BY t.id_canal, fecha
    """)


@st.cache_data(ttl=3600)
def get_pred_segmentacion() -> pd.DataFrame:
    """Segmentación de productos (KMEANS): cada SKU con su cluster y features."""
    return _query(f"""
        SELECT *
        FROM `{PROJECT}.ali1_predictive.pred_segmentacion_productos_v2`
    """)


@st.cache_data(ttl=3600)
def get_eval_segmentacion() -> pd.DataFrame:
    """Métricas de calidad del clustering (Davies-Bouldin, distancia media)."""
    return _query(f"""
        SELECT davies_bouldin_index, mean_squared_distance
        FROM `{PROJECT}.ali1_predictive.eval_segmentacion_productos_v2`
    """)
# ╔══ FIN CAPA PREDICTIVA v2 ═════════════════════════════════════════════════╝


@st.cache_data(ttl=3600)
def get_frecuencia_compra(filtros_where: str = "") -> pd.DataFrame:
    where = f"WHERE {filtros_where}" if filtros_where else ""
    return _query(f"""
        SELECT
            COUNT(DISTINCT num_factura) / NULLIF(COUNT(DISTINCT id_cliente), 0) AS frecuencia_compra
        FROM `{PROJECT}.ali1_curated.FACT_VENTAS`
        {where}
    """)
