"""
6.2 Calidad y Perfilamiento de Datos
======================================
Validaciones locales sobre los CSV de origen antes de ingestión a BigQuery.
Ejecutar: python validacion/6/6_2/validacion_calidad_datos.py
"""

import os
import pandas as pd

# ---------------------------------------------------------------------------
# Rutas base (relativas al root del proyecto)
# ---------------------------------------------------------------------------
ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "..")

PATHS = {
    "ventas":     os.path.join(ROOT, "Data_origen", "supuestos", "ventas_alicorp.csv"),
    "inventario": os.path.join(ROOT, "Data_origen", "supuestos", "supuestos v2", "inventario_alicorp.csv"),
    "clientes":   os.path.join(ROOT, "Data_origen", "clientes_alicorp.csv"),
    "fill_rate":  os.path.join(ROOT, "Data_origen", "fill_rate_despachos.csv"),
    "promociones":os.path.join(ROOT, "Data_origen", "promociones_alicorp.csv"),
    "inversion":  os.path.join(ROOT, "Data_origen", "inversion_promocional_soles.csv"),
}

SEPARATOR = "=" * 70


def _pct(n, total):
    return f"{n:,} ({n / total:.1%})" if total else "0"


# ---------------------------------------------------------------------------
# VQ-01: Duplicados / re-exportaciones en ventas_alicorp
# ---------------------------------------------------------------------------
def vq01_ventas_duplicados():
    print(SEPARATOR)
    print("VQ-01 | ventas_alicorp.csv — Duplicados por estado_linea = DUPLICADO")
    print(SEPARATOR)

    df = pd.read_csv(PATHS["ventas"])
    total = len(df)

    # Regla: registros marcados como DUPLICADO
    duplicados = df[df["estado_linea"] == "DUPLICADO"]
    n_dup = len(duplicados)

    # Regla adicional: pares (num_factura, id_linea_venta) repetidos
    dup_llave = df.duplicated(subset=["num_factura", "id_linea_venta"], keep=False).sum()

    print(f"  Total registros            : {total:,}")
    print(f"  estado_linea = DUPLICADO   : {_pct(n_dup, total)}")
    print(f"  Dups exactos (factura+línea): {_pct(dup_llave, total)}")

    # Tratamiento propuesto: conservar solo ACTIVO
    df_trusted = df[df["estado_linea"] == "ACTIVO"]
    print(f"  Tras filtro ACTIVO         : {len(df_trusted):,} registros")

    status = "FALLA" if n_dup > 0 else "OK"
    print(f"  Resultado                  : {status}")
    print()
    return {"regla": "VQ-01", "estado": status, "afectados": n_dup, "total": total}


# ---------------------------------------------------------------------------
# VQ-02: Stock negativo en inventario_alicorp
# ---------------------------------------------------------------------------
def vq02_inventario_stock_negativo():
    print(SEPARATOR)
    print("VQ-02 | inventario_alicorp.csv — stock_disponible >= 0")
    print(SEPARATOR)

    df = pd.read_csv(PATHS["inventario"])
    total = len(df)

    negativos = df[df["stock_disponible"] < 0]
    n_neg = len(negativos)

    print(f"  Total registros             : {total:,}")
    print(f"  stock_disponible < 0        : {_pct(n_neg, total)}")

    if n_neg > 0:
        print("\n  Muestra de registros afectados:")
        print(
            negativos[["id_snapshot_inv", "fecha_snapshot", "id_almacen",
                        "stock_disponible", "motivo_ajuste"]]
            .head(5)
            .to_string(index=False)
        )

    # Tratamiento: filtrar en raw → trusted
    df_trusted = df[df["stock_disponible"] >= 0]
    print(f"\n  Tras filtro stock >= 0      : {len(df_trusted):,} registros")

    status = "FALLA" if n_neg > 0 else "OK"
    print(f"  Resultado                   : {status}")
    print()
    return {"regla": "VQ-02", "estado": status, "afectados": n_neg, "total": total}


# ---------------------------------------------------------------------------
# VQ-03: Claves id_promocion no homologadas (Trade Marketing vs SAP)
# ---------------------------------------------------------------------------
def vq03_promociones_claves():
    print(SEPARATOR)
    print("VQ-03 | promociones / inversion_promocional — id_promocion sin SAP")
    print(SEPARATOR)

    df_p = pd.read_csv(PATHS["promociones"])
    df_i = pd.read_csv(PATHS["inversion"])

    total_p = len(df_p)
    total_i = len(df_i)

    # Campaña sin clave SAP en tabla de promociones
    sin_sap_p = df_p["id_promocion_sap"].isna().sum() + (df_p["id_promocion_sap"] == "").sum()
    # Registros de inversión sin clave SAP ni TM
    sin_sap_i = df_i["id_promocion_sap"].isna().sum() + (df_i["id_promocion_sap"] == "").sum()
    sin_tm_i  = df_i["id_promocion_tm"].isna().sum()  + (df_i["id_promocion_tm"]  == "").sum()

    # id_promocion_tm que existen en promociones pero no tienen contraparte en inversión
    tm_promo = set(df_p["id_promocion_tm"].dropna())
    tm_inv   = set(df_i["id_promocion_tm"].replace("", pd.NA).dropna())
    solo_en_promo = tm_promo - tm_inv

    print(f"  Total campañas (promociones): {total_p:,}")
    print(f"  Sin id_promocion_sap        : {_pct(sin_sap_p, total_p)}")
    print(f"  Total registros (inversion) : {total_i:,}")
    print(f"  Sin id_promocion_sap        : {_pct(sin_sap_i, total_i)}")
    print(f"  Sin id_promocion_tm         : {_pct(sin_tm_i,  total_i)}")
    print(f"  Campañas TM sin cruce SAP   : {len(solo_en_promo):,}")

    status = "FALLA" if sin_sap_p > 0 else "OK"
    print(f"  Resultado                   : {status}")
    print()
    return {"regla": "VQ-03", "estado": status, "afectados": sin_sap_p, "total": total_p}


# ---------------------------------------------------------------------------
# VQ-04: Nulos en fill_rate_despachos (motivo_rechazo, transportista)
# ---------------------------------------------------------------------------
def vq04_fill_rate_nulos():
    print(SEPARATOR)
    print("VQ-04 | fill_rate_despachos.csv — Nulos en motivo_rechazo y transportista")
    print(SEPARATOR)

    df = pd.read_csv(PATHS["fill_rate"])
    total = len(df)

    motivo_vacio = df["motivo_rechazo"].isna().sum() + (df["motivo_rechazo"] == "").sum()
    trans_vacio  = df["transportista"].isna().sum()  + (df["transportista"]  == "").sum()

    print(f"  Total registros             : {total:,}")
    print(f"  motivo_rechazo vacío        : {_pct(motivo_vacio, total)}")
    print(f"  transportista vacío         : {_pct(trans_vacio, total)}")

    # Despachos rechazados sin motivo (crítico)
    rechazados = df[df["cantidad_rechazada_uds"] > 0] if "cantidad_rechazada_uds" in df.columns else df
    sin_motivo_rechazados = rechazados["motivo_rechazo"].isna().sum() + (rechazados["motivo_rechazo"] == "").sum()
    print(f"  Rechazos sin motivo (crítico): {_pct(sin_motivo_rechazados, len(rechazados))}")

    # Tratamiento: imputar "No especificado"
    df["motivo_rechazo"] = df["motivo_rechazo"].fillna("No especificado").replace("", "No especificado")
    df["transportista"]  = df["transportista"].fillna("No especificado").replace("", "No especificado")
    restantes_m = (df["motivo_rechazo"] == "No especificado").sum()
    restantes_t = (df["transportista"]  == "No especificado").sum()
    print(f"\n  Tras imputación 'No especificado':")
    print(f"    motivo_rechazo imputados  : {restantes_m:,}")
    print(f"    transportista imputados   : {restantes_t:,}")

    status = "FALLA" if trans_vacio > 0 else "OK"
    print(f"  Resultado                   : {status}")
    print()
    return {"regla": "VQ-04", "estado": status, "afectados": trans_vacio, "total": total}


# ---------------------------------------------------------------------------
# VQ-05: Históricos incompletos — clientes dados de baja antes de 2023
# ---------------------------------------------------------------------------
def vq05_clientes_historicos():
    print(SEPARATOR)
    print("VQ-05 | clientes_alicorp.csv — Inactivos antes de 2023 (KPI-10 no comparable)")
    print(SEPARATOR)

    df = pd.read_csv(PATHS["clientes"])
    total = len(df)

    df["fecha_baja_sistema"] = pd.to_datetime(df["fecha_baja_sistema"], errors="coerce")

    inactivos_total    = (df["estado_cliente"] == "INACTIVO").sum()
    inactivos_pre_2023 = (
        (df["estado_cliente"] == "INACTIVO") &
        (df["fecha_baja_sistema"] < "2023-01-01")
    ).sum()

    print(f"  Total clientes              : {total:,}")
    print(f"  Estado INACTIVO             : {_pct(inactivos_total, total)}")
    print(f"  Inactivos antes de 2023     : {_pct(inactivos_pre_2023, total)}")
    print(f"  Restricción aplicada        : KPI-10 (frecuencia de compra) excluye")
    print(f"                                cohortes con baja anterior a 2023-01-01")

    status = "ADVERTENCIA" if inactivos_pre_2023 > 0 else "OK"
    print(f"  Resultado                   : {status}")
    print()
    return {"regla": "VQ-05", "estado": status, "afectados": inactivos_pre_2023, "total": total}


# ---------------------------------------------------------------------------
# Resumen ejecutivo
# ---------------------------------------------------------------------------
def resumen(resultados):
    print(SEPARATOR)
    print("RESUMEN DE VALIDACIONES - Capa Raw -> Trusted")
    print(SEPARATOR)
    print(f"{'Regla':<8} {'Estado':<12} {'Afectados':>12} {'Total':>12} {'%':>8}")
    print("-" * 60)
    for r in resultados:
        pct_str = f"{r['afectados'] / r['total']:.1%}" if r["total"] else "-"
        print(
            f"  {r['regla']:<6} {r['estado']:<12} "
            f"{r['afectados']:>12,} {r['total']:>12,} {pct_str:>8}"
        )
    print(SEPARATOR)
    fallidas = [r for r in resultados if r["estado"] != "OK"]
    print(f"  Validaciones fallidas / con advertencia: {len(fallidas)} de {len(resultados)}")
    print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    print()
    print("  6.2 CALIDAD Y PERFILAMIENTO DE DATOS - Alicorp SIN")
    print(SEPARATOR)
    print()

    resultados = [
        vq01_ventas_duplicados(),
        vq02_inventario_stock_negativo(),
        vq03_promociones_claves(),
        vq04_fill_rate_nulos(),
        vq05_clientes_historicos(),
    ]

    resumen(resultados)
