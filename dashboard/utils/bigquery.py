import streamlit as st
from google.cloud import bigquery
import pandas as pd

PROJECT = "sing1261"
CLIENT = bigquery.Client(project=PROJECT)


def _query(sql: str) -> pd.DataFrame:
    return CLIENT.query(sql).to_dataframe()


@st.cache_data(ttl=3600)
def get_comercial() -> pd.DataFrame:
    return _query(f"""
        SELECT *
        FROM `{PROJECT}.ali1_kpi.CUBO_COMERCIAL`
    """)


@st.cache_data(ttl=3600)
def get_facturas() -> pd.DataFrame:
    return _query(f"""
        SELECT *
        FROM `{PROJECT}.ali1_kpi.CUBO_FACTURAS`
    """)


@st.cache_data(ttl=3600)
def get_inventario() -> pd.DataFrame:
    return _query(f"""
        SELECT *
        FROM `{PROJECT}.ali1_kpi.CUBO_INVENTARIO`
    """)


@st.cache_data(ttl=3600)
def get_frecuencia_compra(filtros_where: str = "") -> pd.DataFrame:
    where = f"WHERE {filtros_where}" if filtros_where else ""
    return _query(f"""
        SELECT
            COUNT(DISTINCT num_factura) / NULLIF(COUNT(DISTINCT id_cliente), 0) AS frecuencia_compra
        FROM `{PROJECT}.ali1_curated.FACT_VENTAS`
        {where}
    """)
