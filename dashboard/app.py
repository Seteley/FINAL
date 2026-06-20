import streamlit as st
import os

st.set_page_config(
    page_title="Alicorp Analytics",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="collapsed",
)

st.markdown("""
<style>
    #MainMenu                  { display: none !important; }
    footer                     { display: none !important; }
    [data-testid="stToolbar"]  { display: none !important; }
    [data-testid="stHeader"]   { display: none !important; }
    section[data-testid="stSidebar"] { display: none !important; }

    /* Canvas */
    .stApp { background-color: #e0eece; }
    .block-container { padding-top: 0.5rem; padding-bottom: 1rem; }

    /* KPI cards */
    .kpi-card {
        background-color: white;
        border-radius: 8px;
        padding: 14px 16px;
        margin: 3px 0;
        box-shadow: 0 1px 4px rgba(0,0,0,0.10);
        min-height: 110px;
    }
    .kpi-value { font-size: 1.6rem; font-weight: 700; color: #1a1a1a; line-height: 1.1; }
    .kpi-label { font-size: 0.70rem; color: #555; text-transform: uppercase;
                 letter-spacing: 0.05em; margin-bottom: 4px; }
    .kpi-meta  { font-size: 0.70rem; margin-top: 5px; color: #666; }

    /* Gráficas */
    .grafica-box {
        background: white; border-radius: 8px; padding: 12px;
        box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 8px;
    }
    h1, h2, h3, h4 { color: #1a1a1a !important; }
    hr { border-color: rgba(0,0,0,0.12); }

    /* Expander de filtros */
    .streamlit-expanderHeader {
        background-color: #c8001e !important;
        color: white !important;
        border-radius: 6px !important;
        font-weight: 600 !important;
    }
    .streamlit-expanderContent {
        background-color: #fff8f8 !important;
        border: 1px solid #c8001e !important;
        border-radius: 0 0 6px 6px !important;
    }
</style>
""", unsafe_allow_html=True)

import paginas.comercial  as pag_comercial
import paginas.inventario as pag_inventario
from utils.bigquery import get_comercial, get_facturas, get_inventario

# Cargar datos (cacheados)
df_com = get_comercial()
df_fac = get_facturas()
df_inv = get_inventario()

# Navegación por tabs
tab_com, tab_inv = st.tabs(["📈 Comercial", "📦 Inventario"])

# ── Tab Comercial ─────────────────────────────────────────────────────────────
with tab_com:
    with st.expander("🔍 Filtros", expanded=False):
        fc1, fc2, fc3, fc4, fc5 = st.columns(5)
        with fc1:
            sel_periodo = st.multiselect("Periodo",
                sorted(df_com["anio_mes"].dropna().unique().tolist()), key="c_periodo")
        with fc2:
            sel_canal = st.multiselect("Canal",
                sorted(df_com["nombre_canal"].dropna().unique().tolist()), key="c_canal")
        with fc3:
            sel_marca = st.multiselect("Marca",
                sorted(df_com["marca"].dropna().unique().tolist()), key="c_marca")
        with fc4:
            sel_region = st.multiselect("Región",
                sorted(df_com["Departamento"].dropna().unique().tolist()), key="c_region")
        with fc5:
            sel_segmento = st.multiselect("Segmento",
                sorted(df_com["tipo_canal"].dropna().unique().tolist()), key="c_segmento")

    filtros_com = dict(periodo=sel_periodo, canal=sel_canal, marca=sel_marca,
                       region=sel_region, segmento=sel_segmento)
    pag_comercial.render(df_com, df_fac, filtros_com)

# ── Tab Inventario ────────────────────────────────────────────────────────────
with tab_inv:
    with st.expander("🔍 Filtros", expanded=False):
        fi1, fi2, fi3 = st.columns(3)
        with fi1:
            sel_periodo_i = st.multiselect("Periodo",
                sorted(df_inv["anio_mes"].dropna().unique().tolist()), key="i_periodo")
        with fi2:
            sel_almacen = st.multiselect("Almacén",
                sorted(df_inv["nombre_almacen"].dropna().unique().tolist()), key="i_almacen")
        with fi3:
            sel_categoria = st.multiselect("Categoría",
                sorted(df_inv["categoria"].dropna().unique().tolist()), key="i_categoria")

    filtros_inv = dict(periodo=sel_periodo_i, almacen=sel_almacen, categoria=sel_categoria)
    pag_inventario.render(df_inv, filtros_inv)
