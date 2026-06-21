import streamlit as st
import plotly.express as px
import plotly.graph_objects as go
import pandas as pd
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

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

# Paleta para clusters de segmentación
COLORES_CLUSTER = ["#c8001e", "#2196F3", "#4CAF50", "#FF9800", "#9C27B0", "#00BCD4"]


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


def _kpi_card(label: str, value: str, meta_texto: str = "", cumple: bool | None = None):
    semaforo = _semaforo_html(cumple) if cumple is not None else ""
    meta_html = f"<div class='kpi-meta'><small>{meta_texto}</small></div>" if meta_texto else ""
    st.markdown(
        f"<div class='kpi-card'>"
        f"<div class='kpi-label'>{label}</div>"
        f"<div style='display:flex;align-items:center;'>"
        f"<span class='kpi-value'>{value}</span>{semaforo}"
        f"</div>{meta_html}</div>",
        unsafe_allow_html=True,
    )


def render(df_hist, df_pred, df_seg, eval_seg, filtros):
    st.markdown("## Dashboard Predictivo")

    # ════════════════════════════════════════════════════════════════════════
    # SECCIÓN A — PRONÓSTICO DE VENTAS (ARIMA_PLUS_XREG)
    # ════════════════════════════════════════════════════════════════════════
    st.markdown("### 🔮 Pronóstico de Ventas por Canal — Próximos 90 días (Q1 2026)")
    st.caption("Modelo ARIMA_PLUS_XREG · BigQuery ML · regresores: feriados + inversión promocional")

    dfp = df_pred.copy()
    dfh = df_hist.copy()
    if filtros.get("canal"):
        dfp = dfp[dfp["nombre_canal"].isin(filtros["canal"])]
        dfh = dfh[dfh["nombre_canal"].isin(filtros["canal"])]

    # Histórico solo 2025 para dar contexto sin saturar
    dfh = dfh[pd.to_datetime(dfh["fecha"]).dt.year == 2025]

    if dfp.empty:
        st.info("No hay pronóstico para los canales seleccionados.")
    else:
        col_tot, col_canal = st.columns([3, 2])

        with col_tot:
            st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
            st.markdown("**Total: Histórico 2025 + Pronóstico 2026 (banda IC 90%)**")
            hist_tot = dfh.groupby("fecha", as_index=False)["ventas_netas_soles"].sum()
            pred_tot = (
                dfp.groupby("fecha", as_index=False)
                .agg(venta=("venta_pronostico", "sum"),
                     lim_inf=("lim_inf", "sum"), lim_sup=("lim_sup", "sum"))
                .sort_values("fecha")
            )
            fig = go.Figure()
            # Banda IC
            fig.add_trace(go.Scatter(
                x=pred_tot["fecha"], y=pred_tot["lim_sup"], mode="lines",
                line=dict(width=0), showlegend=False, hoverinfo="skip"))
            fig.add_trace(go.Scatter(
                x=pred_tot["fecha"], y=pred_tot["lim_inf"], mode="lines",
                line=dict(width=0), fill="tonexty", fillcolor="rgba(200,0,30,0.12)",
                name="IC 90%", hoverinfo="skip"))
            # Histórico
            fig.add_trace(go.Scatter(
                x=hist_tot["fecha"], y=hist_tot["ventas_netas_soles"], mode="lines",
                line=dict(color="#457b9d", width=1.5), name="Histórico 2025"))
            # Pronóstico
            fig.add_trace(go.Scatter(
                x=pred_tot["fecha"], y=pred_tot["venta"], mode="lines",
                line=dict(color="#c8001e", width=2), name="Pronóstico 2026"))
            fig.update_layout(**PLOT_LAYOUT, height=320, xaxis=dict(tickangle=45),
                              margin=dict(l=20, r=20, t=10, b=10),
                              legend=dict(orientation="h", y=-0.25, font_size=10))
            st.plotly_chart(fig, width='stretch')
            st.markdown('</div>', unsafe_allow_html=True)

        with col_canal:
            st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
            st.markdown("**Pronóstico 2026 por Canal**")
            fig_c = px.line(
                dfp, x="fecha", y="venta_pronostico", color="nombre_canal",
                color_discrete_map=COLORES_CANAL,
                labels={"venta_pronostico": "Venta diaria (S/)", "fecha": "", "nombre_canal": "Canal"},
            )
            fig_c.update_layout(**PLOT_LAYOUT, height=320, xaxis=dict(tickangle=45),
                                legend=dict(orientation="h", y=-0.35, font_size=9))
            st.plotly_chart(fig_c, width='stretch')
            st.markdown('</div>', unsafe_allow_html=True)

        # Resumen por canal
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Resumen del Pronóstico por Canal (Q1 2026)**")
        res = (
            dfp.groupby("nombre_canal", as_index=False)
            .agg(media=("venta_pronostico", "mean"), sup=("lim_sup", "mean"))
        )
        res["Venta diaria media"] = res["media"].map(lambda x: f"S/ {x:,.0f}")
        res["IC 90% (±)"] = (res["sup"] - res["media"]).map(lambda x: f"± S/ {x:,.0f}")
        st.dataframe(
            res[["nombre_canal", "Venta diaria media", "IC 90% (±)"]]
            .rename(columns={"nombre_canal": "Canal"}),
            width='stretch', hide_index=True,
        )
        st.markdown('</div>', unsafe_allow_html=True)

    st.markdown("---")

    # ════════════════════════════════════════════════════════════════════════
    # SECCIÓN B — SEGMENTACIÓN DE PRODUCTOS (KMEANS)
    # ════════════════════════════════════════════════════════════════════════
    st.markdown("### 🧩 Segmentación de Productos (Portafolio)")
    st.caption("Modelo KMEANS · BigQuery ML · features: precio, margen, rotación, ventas, devolución")

    dfs = df_seg.copy()
    dfs["cluster"] = dfs["cluster"].astype(str)
    if filtros.get("cluster"):
        dfs = dfs[dfs["cluster"].isin([str(c) for c in filtros["cluster"]])]
    if filtros.get("categoria"):
        dfs = dfs[dfs["categoria"].isin(filtros["categoria"])]

    if dfs.empty:
        st.info("No hay productos para los filtros seleccionados.")
    else:
        davies = eval_seg["davies_bouldin_index"].iloc[0] if not eval_seg.empty else None

        k1, k2, k3 = st.columns(3)
        with k1:
            _kpi_card("SKUs segmentados", f"{len(dfs):,}")
        with k2:
            _kpi_card("Nº de Clusters", f"{dfs['cluster'].nunique()}")
        with k3:
            _kpi_card("Davies-Bouldin", f"{davies:.3f}" if davies is not None else "—",
                      "menor = mejor separación")

        col_sc, col_bar = st.columns([3, 2])

        with col_sc:
            st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
            st.markdown("**Mapa de Segmentos: Precio vs Margen (tamaño = ventas)**")
            fig_sc = px.scatter(
                dfs, x="precio_lista_soles", y="margen_pct",
                color="cluster", size="ventas_netas",
                color_discrete_sequence=COLORES_CLUSTER,
                hover_name="nombre_sku",
                hover_data={"categoria": True, "ventas_netas": ":,.0f",
                            "precio_lista_soles": ":.1f", "margen_pct": ":.1f", "cluster": False},
                labels={"precio_lista_soles": "Precio lista (S/)", "margen_pct": "Margen %",
                        "cluster": "Cluster"},
                size_max=40,
            )
            fig_sc.update_layout(**PLOT_LAYOUT, height=340,
                                 margin=dict(l=20, r=20, t=10, b=10),
                                 legend=dict(orientation="h", y=-0.25, font_size=10))
            st.plotly_chart(fig_sc, width='stretch')
            st.markdown('</div>', unsafe_allow_html=True)

        with col_bar:
            st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
            st.markdown("**Ventas Netas por Cluster**")
            df_cl = (
                dfs.groupby("cluster", as_index=False)
                .agg(ventas=("ventas_netas", "sum"), skus=("id_producto", "count"))
                .sort_values("cluster")
            )
            fig_b = px.bar(
                df_cl, x="cluster", y="ventas", color="cluster",
                color_discrete_sequence=COLORES_CLUSTER,
                text="skus",
                labels={"ventas": "Ventas Netas (S/)", "cluster": "Cluster"},
            )
            fig_b.update_traces(texttemplate="%{text} SKUs", textposition="outside")
            fig_b.update_layout(**PLOT_LAYOUT, height=340, showlegend=False,
                                margin=dict(l=20, r=20, t=20, b=10))
            st.plotly_chart(fig_b, width='stretch')
            st.markdown('</div>', unsafe_allow_html=True)

        # Tabla de SKUs
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Productos por Segmento**")
        df_tab = dfs.sort_values(["cluster", "ventas_netas"], ascending=[True, False]).copy()
        df_tab["Precio"] = df_tab["precio_lista_soles"].map(lambda x: f"S/ {x:,.1f}")
        df_tab["Margen %"] = df_tab["margen_pct"].map(lambda x: f"{x:.1f}%")
        df_tab["Ventas Netas"] = df_tab["ventas_netas"].map(lambda x: f"S/ {x:,.0f}")
        st.dataframe(
            df_tab[["cluster", "nombre_sku", "categoria", "Precio", "Margen %", "Ventas Netas"]]
            .rename(columns={"cluster": "Cluster", "nombre_sku": "SKU", "categoria": "Categoría"}),
            width='stretch', hide_index=True, height=360,
        )
        st.markdown('</div>', unsafe_allow_html=True)
