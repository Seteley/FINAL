"""
Validación de calidad de datos — Capa RAW (ali1_raw)
Proyecto: sing1261

Ejecuta cada consulta de validacion_raw.sql de forma independiente
y presenta los resultados con un semáforo de estado.

Uso:
    python validacion/raw/run_validacion_raw.py
    python validacion/raw/run_validacion_raw.py --solo V06  # una sola validación
    python validacion/raw/run_validacion_raw.py --resumen    # sólo el resumen ejecutivo
"""

import argparse
import sys
import time
from pathlib import Path

from google.cloud import bigquery

PROJECT = "sing1261"
DATASET = "ali1_raw"

# ─── Definición de cada validación ───────────────────────────────────────────
# Cada entrada: (clave, descripción, valores_esperados_dict_opcional)

VALIDACIONES = [
    (
        "V01",
        "ventas_alicorp — Conteo total y estado_linea",
        {"total_filas": 503998, "filas_duplicado": 3998, "filas_activo": 500000},
    ),
    (
        "V02",
        "ventas_alicorp — Patrón _DUP en id_linea_venta de duplicados",
        {"duplicados_con_sufijo_dup": 3998, "duplicados_sin_sufijo_dup": 0},
    ),
    (
        "V03",
        "ventas_alicorp — Consistencia numérica en filas ACTIVO",
        {
            "cant_vendida_cero_o_neg": 0,
            "precio_unitario_cero_o_neg": 0,
            "ventas_netas_negativas": 0,
        },
    ),
    (
        "V04",
        "fill_rate_despachos — NULLs en transportista y motivo_rechazo",
        None,  # se imprime el resultado, sin valor esperado fijo
    ),
    (
        "V05",
        "fill_rate_despachos — Consistencia flags OTIF (on_time AND in_full)",
        {"otif_inconsistente": 0},
    ),
    (
        "V06",
        "inventario_alicorp — Stock disponible negativo",
        {"stock_negativo": 1640},
    ),
    (
        "V07",
        "inventario_alicorp — flag_ajuste_pendiente vs stock negativo",
        {"neg_con_flag_ajuste_n": 0, "neg_con_flag_ajuste_null": 0},
    ),
    (
        "V08",
        "clientes_alicorp — NULLs en direccion_fiscal",
        {"total_clientes": 300, "direccion_null": 27},
    ),
    (
        "V09",
        "clientes_alicorp — NULLs por cohorte pre/post 2022",
        None,
    ),
    (
        "V10",
        "productos_alicorp — cod_sap con sufijo _DUP",
        {"total_productos": 78, "cod_sap_con_dup": 2},
    ),
    (
        "V11",
        "productos_alicorp — Detalle de SKUs con cod_sap duplicado",
        None,
    ),
    (
        "V12",
        "promociones_alicorp — NULLs y formato en id_promocion_sap",
        {"id_sap_null": 50},
    ),
    (
        "V13",
        "metas_comerciales_raw — Versiones y filas aprobadas",
        {"total_filas": 655, "filas_aprobadas": 216},
    ),
    (
        "V14",
        "metas_comerciales_raw — Distribución por version_meta",
        None,
    ),
    (
        "V15",
        "devoluciones_alicorp — Estado y NULLs en nota_credito",
        None,
    ),
    (
        "V16",
        "inversion_promocional — Orphan keys vs promociones",
        {"id_tm_sin_match_en_promociones": 0},
    ),
    (
        "V17",
        "RESUMEN EJECUTIVO — Semáforo de todos los datasets",
        None,
    ),
]


def cargar_sql(ruta_sql: Path) -> dict[str, str]:
    """Parsea el SQL en bloques separados por comentarios [Vxx]."""
    texto = ruta_sql.read_text(encoding="utf-8")
    bloques: dict[str, str] = {}
    actual_key = None
    actual_lines: list[str] = []

    for linea in texto.splitlines():
        if linea.strip().startswith("-- [V") and "]" in linea:
            if actual_key:
                bloques[actual_key] = "\n".join(actual_lines).strip()
            actual_key = linea.strip().split("[")[1].split("]")[0]
            actual_lines = []
        else:
            actual_lines.append(linea)

    if actual_key:
        bloques[actual_key] = "\n".join(actual_lines).strip()

    return bloques


def evaluar_resultado(df_rows: list[dict], esperado: dict | None) -> str:
    """Retorna PASS / WARN / FAIL / INFO."""
    if esperado is None:
        return "INFO"
    if not df_rows:
        return "FAIL"

    row = df_rows[0]
    for campo, valor_esp in esperado.items():
        valor_real = row.get(campo)
        if valor_real is None:
            return "WARN"
        # Convertir a int para comparar
        try:
            if int(valor_real) != int(valor_esp):
                return "FAIL"
        except (ValueError, TypeError):
            return "WARN"

    return "PASS"


SEMAFORO = {
    "PASS": "\033[92m[PASS]\033[0m",
    "FAIL": "\033[91m[FAIL]\033[0m",
    "WARN": "\033[93m[WARN]\033[0m",
    "INFO": "\033[94m[INFO]\033[0m",
}


def imprimir_tabla(rows: list[bigquery.Row]) -> None:
    if not rows:
        print("  (sin resultados)")
        return
    nombres = list(rows[0].keys())
    anchos = [max(len(str(n)), max(len(str(r[n])) for r in rows)) for n in nombres]
    sep = "  " + "-+-".join("-" * a for a in anchos)
    header = "  " + " | ".join(str(n).ljust(a) for n, a in zip(nombres, anchos))
    print(sep)
    print(header)
    print(sep)
    for row in rows:
        print("  " + " | ".join(str(row[n]).ljust(a) for n, a in zip(nombres, anchos)))
    print(sep)


def ejecutar_validacion(
    client: bigquery.Client,
    clave: str,
    descripcion: str,
    sql: str,
    esperado: dict | None,
) -> str:
    print(f"\n{'-'*70}")
    print(f"  {clave} - {descripcion}")
    print(f"{'-'*70}")

    if not sql:
        print("  [ERROR] Consulta SQL no encontrada en el archivo.")
        return "ERROR"

    t0 = time.time()
    try:
        job = client.query(sql)
        rows = list(job.result())
        elapsed = time.time() - t0
        rows_dict = [dict(r) for r in rows]
        imprimir_tabla(rows)
        estado = evaluar_resultado(rows_dict, esperado)
        icono = SEMAFORO.get(estado, estado)
        if esperado:
            exp_str = ", ".join(f"{k}={v}" for k, v in esperado.items())
            print(f"\n  {icono}  ({elapsed:.1f}s)  Esperado: {exp_str}")
        else:
            print(f"\n  {icono}  ({elapsed:.1f}s)  Resultado informativo")
        return estado
    except Exception as exc:
        print(f"  \033[91m[ERROR]\033[0m {exc}")
        return "ERROR"


def main() -> None:
    parser = argparse.ArgumentParser(description="Validación calidad RAW — ali1_raw")
    parser.add_argument("--solo", metavar="Vxx", help="Ejecutar sólo esta validación (ej. V06)")
    parser.add_argument("--resumen", action="store_true", help="Ejecutar sólo V17 (resumen ejecutivo)")
    args = parser.parse_args()

    ruta_sql = Path(__file__).parent / "validacion_raw.sql"
    if not ruta_sql.exists():
        print(f"[ERROR] No se encontró {ruta_sql}")
        sys.exit(1)

    bloques_sql = cargar_sql(ruta_sql)
    client = bigquery.Client(project=PROJECT)

    # Filtro de validaciones a correr
    if args.resumen:
        validaciones_a_correr = [v for v in VALIDACIONES if v[0] == "V17"]
    elif args.solo:
        clave_filtro = args.solo.upper()
        validaciones_a_correr = [v for v in VALIDACIONES if v[0] == clave_filtro]
        if not validaciones_a_correr:
            print(f"[ERROR] Validación '{clave_filtro}' no encontrada.")
            sys.exit(1)
    else:
        validaciones_a_correr = VALIDACIONES

    print("\n" + "=" * 70)
    print("  VALIDACIÓN DE CALIDAD DE DATOS — CAPA RAW")
    print(f"  Proyecto: {PROJECT}  |  Dataset: {DATASET}")
    print(f"  Total validaciones: {len(validaciones_a_correr)}")
    print("=" * 70)

    resultados: dict[str, str] = {}
    for clave, descripcion, esperado in validaciones_a_correr:
        sql = bloques_sql.get(clave, "")
        estado = ejecutar_validacion(client, clave, descripcion, sql, esperado)
        resultados[clave] = estado

    # ─── Resumen final ────────────────────────────────────────────────────────
    print("\n" + "=" * 70)
    print("  RESUMEN DE RESULTADOS")
    print("=" * 70)
    conteo = {"PASS": 0, "FAIL": 0, "WARN": 0, "INFO": 0, "ERROR": 0}
    for clave, estado in resultados.items():
        icono = SEMAFORO.get(estado, estado)
        desc = next((d for c, d, _ in VALIDACIONES if c == clave), "")
        print(f"  {icono}  {clave} — {desc}")
        conteo[estado] = conteo.get(estado, 0) + 1

    print("\n" + "-" * 70)
    print(
        f"  PASS={conteo['PASS']}  FAIL={conteo['FAIL']}  "
        f"WARN={conteo['WARN']}  INFO={conteo['INFO']}  ERROR={conteo['ERROR']}"
    )
    print("=" * 70 + "\n")

    if conteo["FAIL"] > 0 or conteo["ERROR"] > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
