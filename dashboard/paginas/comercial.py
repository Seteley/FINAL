import streamlit as st
import plotly.express as px
import plotly.graph_objects as go
import pandas as pd
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from utils.bigquery import get_comercial, get_facturas, get_frecuencia_compra

# Coordenadas aproximadas de departamentos del Perú
PERU_COORDS = {
    "Ancash":        (-9.53,   -77.53),
    "Apurimac":      (-13.63,  -73.08),
    "Arequipa":      (-16.41,  -71.54),
    "Ayacucho":      (-13.16,  -74.22),
    "Cajamarca":     (-7.16,   -78.50),
    "Cusco":         (-13.53,  -71.97),
    "Huancavelica":  (-12.79,  -74.97),
    "Huanuco":       (-9.93,   -76.24),
    "Ica":           (-14.07,  -75.73),
    "Junin":         (-12.07,  -75.20),
    "La Libertad":   (-8.11,   -79.03),
    "Lambayeque":    (-6.77,   -79.84),
    "Lima":          (-12.05,  -77.04),
    "Loreto":        (-3.75,   -73.25),
    "Madre de Dios": (-12.59,  -69.19),
    "Moquegua":      (-17.19,  -70.93),
    "Pasco":         (-10.69,  -75.21),
    "Piura":         (-5.19,   -80.63),
    "Puno":          (-15.84,  -70.02),
    "San Martin":    (-6.04,   -76.97),
    "Tacna":         (-18.01,  -70.25),
    "Tumbes":        (-3.57,   -80.45),
    "Ucayali":       (-8.38,   -74.55),
    "Amazonas":      (-4.52,   -77.87),
    "Callao":        (-12.05,  -77.13),
}

PLOT_LAYOUT = dict(
    paper_bgcolor="white",
    plot_bgcolor="white",
    font_color="#1a1a1a",
)

COLORES_CANAL = {
    "B2B Industrial":    "#2196F3",
    "Canal Moderno":     "#FF9800",
    "Canal Tradicional": "#4CAF50",
    "E-Commerce":        "#9C27B0",
    "Exportación":       "#F44336",
    "HoReCa":            "#00BCD4",
}

COLORES_LN = [
    "#4FC3F7", "#81C784", "#FFB74D", "#F06292",
    "#AED581", "#BA68C8", "#4DD0E1", "#FFD54F",
]


def _semaforo_html(cumple) -> str:
    rojo    = "#e74c3c" if cumple == False and cumple is not None else "#ddd"
    amarillo= "#f39c12" if cumple is None  else "#ddd"
    verde   = "#27ae60" if cumple == True  else "#ddd"
    return f"""
    <div style="display:inline-flex;flex-direction:column;gap:3px;
                background:#222;border-radius:6px;padding:4px 5px;
                vertical-align:middle;margin-left:8px;">
        <div style="width:12px;height:12px;border-radius:50%;background:{rojo};"></div>
        <div style="width:12px;height:12px;border-radius:50%;background:{amarillo};"></div>
        <div style="width:12px;height:12px;border-radius:50%;background:{verde};"></div>
    </div>"""


def _kpi_card(label: str, value: str, meta_texto: str, cumple: bool | None = None):
    semaforo = _semaforo_html(cumple)
    st.markdown(f"""
    <div class="kpi-card">
        <div class="kpi-label">{label}</div>
        <div style="display:flex;align-items:center;">
            <span class="kpi-value">{value}</span>
            {semaforo}
        </div>
        <div class="kpi-meta"><small>{meta_texto}</small></div>
    </div>
    """, unsafe_allow_html=True)


def _fmt_soles(v: float) -> str:
    if v >= 1_000_000:
        return f"S/ {v/1_000_000:.1f}M"
    if v >= 1_000:
        return f"S/ {v/1_000:.1f}K"
    return f"S/ {v:,.0f}"


def _fmt_num(v: float) -> str:
    return f"{v:,.0f}"


def render(df_com, df_fac, filtros):
    st.markdown("## Dashboard Comercial")

    # ── Aplicar filtros ───────────────────────────────────────────────────────
    df   = df_com.copy()
    df_f = df_fac.copy()

    if filtros.get("periodo"):
        df   = df[df["anio_mes"].isin(filtros["periodo"])]
        df_f = df_f[df_f["anio_mes"].isin(filtros["periodo"])]
    if filtros.get("canal"):
        df   = df[df["nombre_canal"].isin(filtros["canal"])]
        df_f = df_f[df_f["nombre_canal"].isin(filtros["canal"])]
    if filtros.get("marca"):
        df = df[df["marca"].isin(filtros["marca"])]
    if filtros.get("region"):
        df   = df[df["Departamento"].isin(filtros["region"])]
        df_f = df_f[df_f["Departamento"].isin(filtros["region"])]
    if filtros.get("segmento"):
        df   = df[df["tipo_canal"].isin(filtros["segmento"])]
        df_f = df_f[df_f["tipo_canal"].isin(filtros["segmento"])]

    # ── Calcular KPIs ─────────────────────────────────────────────────────────
    ventas_netas    = df["ventas_netas"].sum()
    margen_bruto    = df["margen_bruto"].sum()
    inversion_promo = df["inversion_promo"].sum()
    cantidad_vend   = df["cantidad_vendida"].sum()
    unid_devueltas  = df["unidades_devueltas"].sum()

    margen_pct      = margen_bruto / ventas_netas * 100 if ventas_netas else 0
    tasa_devolucion = unid_devueltas / cantidad_vend * 100 if cantidad_vend else 0
    roi_pct         = (margen_bruto - inversion_promo) / inversion_promo * 100 if inversion_promo else 0

    num_facturas    = df_f["num_facturas"].sum()
    ticket_promedio = ventas_netas / num_facturas if num_facturas else 0

    where_parts = []
    if filtros.get("periodo"):
        vals = ", ".join(f"'{p}'" for p in filtros["periodo"])
        where_parts.append(f"FORMAT_DATE('%Y%m', DATE(fecha)) IN ({vals})")
    if filtros.get("canal"):
        vals = ", ".join(f"'{c}'" for c in filtros["canal"])
        where_parts.append(
            f"id_canal IN (SELECT id_canal FROM `sing1261.ali1_curated.DIM_CANAL` WHERE nombre_canal IN ({vals}))"
        )
    frecuencia_df = get_frecuencia_compra(" AND ".join(where_parts) if where_parts else "")
    frecuencia    = frecuencia_df["frecuencia_compra"].iloc[0] if not frecuencia_df.empty else 0

    # Metas: deduplicar por canal+periodo para no multiplicarlas por filas de producto/geo
    df_meta        = df.drop_duplicates(subset=["nombre_canal", "periodo"])
    meta_ventas    = df_meta["meta_ventas_netas"].sum()
    meta_margen_s  = df_meta["meta_margen_bruto"].sum()    # SUM en soles
    meta_margen    = df_meta["meta_margen_pct"].mean()
    meta_cantidad  = df_meta["meta_cantidad_vendida"].sum() # SUM de unidades
    meta_ticket    = df_meta["meta_ticket_promedio"].mean()
    meta_frec      = df_meta["meta_frecuencia_compra"].mean()
    meta_roi       = df_meta["meta_roi_pct"].mean()
    meta_devol     = df_meta["meta_tasa_devolucion"].mean()

    # ── Fila 1 KPIs ───────────────────────────────────────────────────────────
    c1, c2, c3, c4 = st.columns(4)
    with c1:
        _kpi_card("KPI-01 Ventas Netas", _fmt_soles(ventas_netas),
                  f"Meta: {_fmt_soles(meta_ventas)}", bool(ventas_netas >= meta_ventas) if meta_ventas else None)
    with c2:
        _kpi_card("KPI-02 Utilidad Bruta", _fmt_soles(margen_bruto),
                  f"Meta: {_fmt_soles(meta_margen_s)}", bool(margen_bruto >= meta_margen_s) if meta_margen_s else None)
    with c3:
        _kpi_card("KPI-03 Margen %", f"{margen_pct:.1f}%",
                  f"Meta: {meta_margen:.1f}%", bool(margen_pct >= meta_margen) if meta_margen else None)
    with c4:
        _kpi_card("KPI-04 Cantidad Vendida", _fmt_num(cantidad_vend),
                  f"Meta: {_fmt_num(meta_cantidad)}", bool(cantidad_vend >= meta_cantidad) if meta_cantidad else None)

    # ── Fila 2 KPIs ───────────────────────────────────────────────────────────
    c5, c6, c7, c8 = st.columns(4)
    with c5:
        _kpi_card("KPI-05 Ticket Promedio", _fmt_soles(ticket_promedio),
                  f"Meta: {_fmt_soles(meta_ticket)}", bool(ticket_promedio >= meta_ticket) if meta_ticket else None)
    with c6:
        _kpi_card("KPI-08 Frecuencia Compra", f"{frecuencia:.1f}",
                  f"Meta: {meta_frec:.1f}", bool(frecuencia >= meta_frec) if meta_frec else None)
    with c7:
        _kpi_card("KPI-11 ROI Promocional", f"{roi_pct:.1f}%",
                  f"Meta: {meta_roi:.1f}%", bool(roi_pct >= meta_roi) if meta_roi else None)
    with c8:
        _kpi_card("KPI Tasa Devolución", f"{tasa_devolucion:.1f}%",
                  f"Meta: {meta_devol:.1f}%", bool(tasa_devolucion <= meta_devol) if meta_devol else None)

    st.markdown("---")

    # ── Gráfica: Participación canal + Mapa ───────────────────────────────────
    col_canal, col_mapa = st.columns([3, 2])

    with col_canal:
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**KPI-06 Participación de Canal x Ventas**")
        df_canal = df.groupby(["anio_mes", "nombre_canal"], as_index=False)["ventas_netas"].sum()
        fig_canal = px.bar(
            df_canal, x="anio_mes", y="ventas_netas", color="nombre_canal",
            color_discrete_map=COLORES_CANAL,
            labels={"ventas_netas": "Ventas Netas (S/)", "anio_mes": "", "nombre_canal": "Canal"},
        )
        fig_canal.update_layout(**PLOT_LAYOUT, height=300, xaxis=dict(tickangle=45),
                                legend=dict(orientation="h", y=-0.3, font_size=10))
        st.plotly_chart(fig_canal, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    with col_mapa:
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Ventas Netas por Región**")
        df_geo = df.groupby("Departamento", as_index=False)["ventas_netas"].sum()
        df_geo["lat"] = df_geo["Departamento"].map(lambda d: PERU_COORDS.get(d, (None, None))[0])
        df_geo["lon"] = df_geo["Departamento"].map(lambda d: PERU_COORDS.get(d, (None, None))[1])
        df_geo = df_geo.dropna(subset=["lat", "lon"])
        fig_mapa = px.scatter_mapbox(
            df_geo,
            lat="lat", lon="lon",
            size="ventas_netas",
            color="ventas_netas",
            color_continuous_scale="Reds",
            hover_name="Departamento",
            hover_data={"ventas_netas": ":,.0f", "lat": False, "lon": False},
            zoom=4, center={"lat": -9.5, "lon": -75.0},
            size_max=40,
        )
        fig_mapa.update_layout(
            mapbox_style="carto-positron",
            paper_bgcolor="white",
            font_color="#1a1a1a",
            height=300,
            coloraxis_showscale=False,
            margin=dict(l=0, r=0, t=0, b=0),
        )
        st.plotly_chart(fig_mapa, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    # ── Tabla KPI-10 (mitad izquierda) + Dona + YTD (mitad derecha) ───────────
    col_tabla, col_derecha = st.columns([3, 2])

    with col_tabla:
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**KPI-10 Productos por Ventas**")
        df_prod = (
            df.groupby(["marca", "nombre_sku"], as_index=False)
            .agg(
                ventas_netas=("ventas_netas", "sum"),
                cantidad_vendida=("cantidad_vendida", "sum"),
                margen_bruto=("margen_bruto", "sum"),
            )
        )
        df_prod["Margen %"] = (df_prod["margen_bruto"] / df_prod["ventas_netas"] * 100).round(1)
        df_prod["Ventas Netas"] = df_prod["ventas_netas"].map(lambda x: f"S/ {x:,.0f}")
        df_prod = df_prod.sort_values("ventas_netas", ascending=False)
        st.dataframe(
            df_prod[["marca", "nombre_sku", "Ventas Netas", "cantidad_vendida", "Margen %"]]
            .rename(columns={
                "marca": "Marca", "nombre_sku": "SKU",
                "cantidad_vendida": "Cantidad",
            }),
            use_container_width=True, hide_index=True, height=420,
        )
        st.markdown('</div>', unsafe_allow_html=True)

    with col_derecha:
        # Dona
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Ventas Netas por Línea de Negocio**")
        df_ln = df.groupby("linea_negocio", as_index=False)["ventas_netas"].sum()
        fig_dona = px.pie(
            df_ln, values="ventas_netas", names="linea_negocio", hole=0.45,
            color_discrete_sequence=COLORES_LN,
        )
        fig_dona.update_traces(textposition="inside", textinfo="percent+label",
                               textfont_size=10)
        fig_dona.update_layout(
            **PLOT_LAYOUT, height=200,
            showlegend=False,
            margin=dict(l=0, r=0, t=10, b=0),
        )
        st.plotly_chart(fig_dona, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

        # YTD
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Ventas Netas YTD por Mes y Año**")
        df_ytd = df.groupby(["anio", "mes", "mes_nombre"], as_index=False)["ventas_netas"].sum()
        df_ytd = df_ytd.sort_values("mes")
        fig_ytd = px.line(
            df_ytd, x="mes_nombre", y="ventas_netas", color="anio",
            markers=True,
            labels={"ventas_netas": "Ventas (S/)", "mes_nombre": "", "anio": "Año"},
            color_discrete_sequence=["#e63946", "#457b9d", "#2a9d8f"],
        )
        fig_ytd.update_layout(
            **PLOT_LAYOUT, height=200,
            xaxis=dict(tickangle=45, tickfont_size=9),
            legend=dict(orientation="h", y=1.15, font_size=10),
        )
        st.plotly_chart(fig_ytd, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)
