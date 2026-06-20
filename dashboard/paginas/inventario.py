import streamlit as st
import plotly.express as px
import plotly.graph_objects as go
import pandas as pd
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from utils.bigquery import get_inventario

PLOT_LAYOUT = dict(
    paper_bgcolor="white",
    plot_bgcolor="white",
    font_color="#1a1a1a",
)


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


def render(df_inv, filtros):
    st.markdown("## Dashboard Gestión Operativa")

    # ── Aplicar filtros ───────────────────────────────────────────────────────
    df = df_inv.copy()
    if filtros.get("periodo"):
        df = df[df["anio_mes"].isin(filtros["periodo"])]
    if filtros.get("almacen"):
        df = df[df["nombre_almacen"].isin(filtros["almacen"])]
    if filtros.get("categoria"):
        df = df[df["categoria"].isin(filtros["categoria"])]

    # ── Calcular KPIs ─────────────────────────────────────────────────────────
    stock_total  = df["stock_disponible"].sum()
    skus_quiebre = df["skus_en_quiebre"].sum()
    total_skus   = df["total_skus"].sum()
    tasa_quiebre = skus_quiebre / total_skus * 100 if total_skus else 0

    demanda_total  = (df["stock_disponible"] / df["dias_cobertura"].replace(0, float("nan"))).sum()
    dias_cobertura = stock_total / demanda_total if demanda_total else 0

    df_meta      = df.drop_duplicates(subset=["nombre_almacen", "periodo"])
    meta_quiebre = float(df_meta["meta_quiebre_pct"].mean())
    meta_dias    = float(df_meta["meta_dias_cobertura"].mean())

    # ── KPI Cards ─────────────────────────────────────────────────────────────
    c1, c2, c3, c4 = st.columns(4)
    with c1:
        _kpi_card("KPI Tasa Quiebre", f"{tasa_quiebre:.1f}%",
                  f"Meta: {meta_quiebre:.1f}%", bool(tasa_quiebre <= meta_quiebre) if meta_quiebre else None)
    with c2:
        _kpi_card("KPI Días Cobertura", f"{dias_cobertura:.1f} días",
                  f"Meta: {meta_dias:.0f} días", bool(dias_cobertura >= meta_dias) if meta_dias else None)
    with c3:
        _kpi_card("Stock Disponible Total", f"{stock_total:,.0f}", "", None)
    with c4:
        _kpi_card("SKUs en Quiebre", f"{int(skus_quiebre):,}", "", None)

    st.markdown("---")

    # ── Fila 1: gauge + quiebre por almacén ───────────────────────────────────
    col_gauge, col_bar_alm = st.columns([1, 3])

    with col_gauge:
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Tasa Quiebre vs Meta**")
        max_gauge = max(tasa_quiebre * 2, meta_quiebre * 2 if meta_quiebre else 10, 10)
        fig_gauge = go.Figure(go.Indicator(
            mode="gauge+number",
            value=tasa_quiebre,
            number={"suffix": "%", "font": {"color": "#1a1a1a", "size": 32}},
            gauge={
                "axis": {"range": [0, max_gauge], "tickcolor": "#333"},
                "bar":  {"color": "#e63946"},
                "bgcolor": "#f5f5f5",
                "threshold": {
                    "line": {"color": "#27ae60", "width": 3},
                    "thickness": 0.75,
                    "value": meta_quiebre or 0,
                },
                "steps": [
                    {"range": [0, meta_quiebre or 0],             "color": "#e8f5e9"},
                    {"range": [meta_quiebre or 0, max_gauge],     "color": "#ffebee"},
                ],
            },
        ))
        fig_gauge.update_layout(
            paper_bgcolor="white", font_color="#1a1a1a", height=260,
            margin=dict(l=20, r=20, t=20, b=10),
        )
        st.plotly_chart(fig_gauge, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    with col_bar_alm:
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Tasa Quiebre % vs Meta por Almacén**")
        df_alm = (
            df.groupby("nombre_almacen", as_index=False)
            .agg(skus_en_quiebre=("skus_en_quiebre", "sum"),
                 total_skus=("total_skus", "sum"),
                 meta_quiebre_pct=("meta_quiebre_pct", "mean"))
        )
        df_alm["tasa"] = df_alm["skus_en_quiebre"] / df_alm["total_skus"] * 100
        fig_alm = go.Figure()
        fig_alm.add_trace(go.Bar(
            x=df_alm["nombre_almacen"], y=df_alm["tasa"],
            name="Tasa Quiebre %", marker_color="#e63946",
        ))
        fig_alm.add_trace(go.Scatter(
            x=df_alm["nombre_almacen"], y=df_alm["meta_quiebre_pct"],
            name="Meta %", mode="lines+markers",
            line=dict(color="#27ae60", width=2), marker=dict(size=6),
        ))
        fig_alm.update_layout(**PLOT_LAYOUT, height=280,
                              xaxis=dict(tickangle=30),
                              margin=dict(l=20, r=120, t=20, b=10),
                              legend=dict(orientation="v", x=1.02, y=1, xanchor="left", yanchor="top"))
        st.plotly_chart(fig_alm, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    # ── Fila 2: treemap + días cobertura ──────────────────────────────────────
    col_tree, col_dias = st.columns([3, 2])

    with col_tree:
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Stock Disponible Total por Almacén**")
        df_tree = df.groupby(["nombre_almacen", "categoria"], as_index=False)["stock_disponible"].sum()
        fig_tree = px.treemap(
            df_tree, path=["nombre_almacen", "categoria"], values="stock_disponible",
            color="stock_disponible",
            color_continuous_scale=["#ffcdd2", "#e63946"],
        )
        fig_tree.update_layout(paper_bgcolor="white", font_color="#1a1a1a",
                               height=300, margin=dict(l=0, r=0, t=10, b=0))
        st.plotly_chart(fig_tree, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    with col_dias:
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Días Cobertura por Almacén**")
        df_dc = (
            df.groupby("nombre_almacen", as_index=False)
            .agg(stock=("stock_disponible", "sum"),
                 meta_dias=("meta_dias_cobertura", "mean"))
        )
        dem = (
            df.assign(dem=df["stock_disponible"] / df["dias_cobertura"].replace(0, float("nan")))
            .groupby("nombre_almacen")["dem"].sum()
        )
        df_dc["dias"] = df_dc.apply(lambda r: r["stock"] / dem.get(r["nombre_almacen"], float("nan")), axis=1)
        df_dc = df_dc.sort_values("dias")
        fig_dc = go.Figure()
        fig_dc.add_trace(go.Bar(
            y=df_dc["nombre_almacen"], x=df_dc["dias"],
            orientation="h", marker_color="#e63946", name="Días cobertura",
        ))
        fig_dc.add_trace(go.Scatter(
            y=df_dc["nombre_almacen"], x=df_dc["meta_dias"],
            mode="markers", marker=dict(color="#27ae60", size=8, symbol="diamond"),
            name="Meta",
        ))
        fig_dc.update_layout(**PLOT_LAYOUT, height=320,
                             margin=dict(l=20, r=120, t=20, b=10),
                             legend=dict(orientation="v", x=1.02, y=1, xanchor="left", yanchor="top"))
        st.plotly_chart(fig_dc, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    # ── Fila 3: series temporales ──────────────────────────────────────────────
    col_serie_q, col_serie_d = st.columns(2)

    with col_serie_q:
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Tasa Quiebre % y Meta por Año y Mes**")
        df_sq = (
            df.groupby(["anio", "mes", "mes_nombre"], as_index=False)
            .agg(skus_q=("skus_en_quiebre", "sum"),
                 total=("total_skus", "sum"),
                 meta=("meta_quiebre_pct", "mean"))
        )
        df_sq["tasa"] = df_sq["skus_q"] / df_sq["total"] * 100
        df_sq = df_sq.sort_values(["anio", "mes"])
        df_sq["periodo"] = df_sq["mes_nombre"].astype(str) + " " + df_sq["anio"].astype(str)
        fig_sq = go.Figure()
        fig_sq.add_trace(go.Scatter(
            x=df_sq["periodo"], y=df_sq["tasa"], fill="tozeroy",
            name="Tasa Quiebre %", line=dict(color="#e63946"),
            fillcolor="rgba(230,57,70,0.15)",
        ))
        fig_sq.add_trace(go.Scatter(
            x=df_sq["periodo"], y=df_sq["meta"],
            name="Meta %", line=dict(color="#27ae60", dash="dot", width=2),
        ))
        fig_sq.update_layout(**PLOT_LAYOUT, height=280,
                             xaxis=dict(tickangle=45, tickfont_size=8),
                             margin=dict(l=20, r=120, t=20, b=10),
                             legend=dict(orientation="v", x=1.02, y=1, xanchor="left", yanchor="top"))
        st.plotly_chart(fig_sq, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    with col_serie_d:
        st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
        st.markdown("**Días Cobertura y Meta por Año y Mes**")
        df_sd = (
            df.groupby(["anio", "mes", "mes_nombre"], as_index=False)
            .agg(stock=("stock_disponible", "sum"),
                 meta=("meta_dias_cobertura", "mean"))
        )
        dem_t = (
            df.assign(dem=df["stock_disponible"] / df["dias_cobertura"].replace(0, float("nan")))
            .groupby(["anio", "mes"])["dem"].sum()
        )
        df_sd["dias"] = df_sd.apply(
            lambda r: r["stock"] / dem_t.get((r["anio"], r["mes"]), float("nan")), axis=1
        )
        df_sd = df_sd.sort_values(["anio", "mes"])
        df_sd["periodo"] = df_sd["mes_nombre"].astype(str) + " " + df_sd["anio"].astype(str)
        fig_sd = go.Figure()
        fig_sd.add_trace(go.Scatter(
            x=df_sd["periodo"], y=df_sd["dias"], fill="tozeroy",
            name="Días Cobertura", line=dict(color="#e63946"),
            fillcolor="rgba(230,57,70,0.15)",
        ))
        fig_sd.add_trace(go.Scatter(
            x=df_sd["periodo"], y=df_sd["meta"],
            name="Meta días", line=dict(color="#27ae60", dash="dot", width=2),
        ))
        fig_sd.update_layout(**PLOT_LAYOUT, height=280,
                             xaxis=dict(tickangle=45, tickfont_size=8),
                             margin=dict(l=20, r=120, t=20, b=10),
                             legend=dict(orientation="v", x=1.02, y=1, xanchor="left", yanchor="top"))
        st.plotly_chart(fig_sd, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    # ── Tabla pivot ────────────────────────────────────────────────────────────
    st.markdown('<div class="grafica-box">', unsafe_allow_html=True)
    st.markdown("**Almacenes por Categoría y Tasa de Quiebre %**")
    df_pivot = (
        df.groupby(["categoria", "nombre_almacen"], as_index=False)
        .agg(skus_q=("skus_en_quiebre", "sum"), total=("total_skus", "sum"))
    )
    df_pivot["tasa"] = (df_pivot["skus_q"] / df_pivot["total"] * 100).round(1)
    tabla = df_pivot.pivot_table(
        index="categoria", columns="nombre_almacen", values="tasa", aggfunc="mean"
    ).round(1).reset_index()
    st.dataframe(tabla, use_container_width=True, hide_index=True)
    st.markdown('</div>', unsafe_allow_html=True)
