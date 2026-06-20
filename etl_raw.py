from datetime import datetime, timezone
from google.cloud import bigquery, storage
from google.cloud.bigquery import LoadJobConfig, SourceFormat, WriteDisposition, TimePartitioning, TimePartitioningType

PROJECT = "sing1261"
BUCKET  = "ali1_bucket"
DATASET = "ali1_raw"

TRANSACCIONALES = {
    "ventas":                "ventas_alicorp.csv",
    "pedidos":               "pedidos_alicorp.csv",
    "devoluciones":          "devoluciones_alicorp.csv",
    "fill_rate":             "fill_rate_despachos.csv",
    "inventario":            "inventario_alicorp.csv",
    "metas":                 "metas_comerciales_raw.csv",
    "promociones":           "promociones_alicorp.csv",
    "inversion_promocional": "inversion_promocional_soles.csv",
}

MAESTROS = {
    "clientes":  "clientes_alicorp.csv",
    "productos": "productos_alicorp.csv",
    "canal":     "canal.csv",
    "geografia": "geografia.csv",
    "almacen":   "almacen.csv",
    "vendedor":  "vendedor.csv",
}


def registrar_control(bq, *, tabla_destino, archivo_origen, fecha_particion,
                      tipo, estado, registros_cargados=None, mensaje_error=None):
    rows = [{
        "tabla_destino":      tabla_destino,
        "archivo_origen":     archivo_origen,
        "fecha_particion":    fecha_particion,
        "tipo":               tipo,
        "estado":             estado,
        "registros_cargados": registros_cargados,
        "mensaje_error":      mensaje_error[:1024] if mensaje_error else None,
        "fecha_carga":        datetime.now(timezone.utc).isoformat(),
    }]
    errores = bq.insert_rows_json(f"{PROJECT}.{DATASET}.etl_control", rows)
    if errores:
        print(f"  [WARN] No se pudo registrar en control: {errores}")


def particiones_ya_procesadas(bq, tabla_destino):
    query = f"""
        SELECT CAST(fecha_particion AS STRING) AS fp
        FROM `{PROJECT}.{DATASET}.etl_control`
        WHERE tabla_destino = '{tabla_destino}'
          AND tipo = 'INCREMENTAL'
          AND estado = 'EXITOSO'
    """
    return {row.fp for row in bq.query(query).result()}


def listar_particiones_gcs(gcs, carpeta):
    prefix = f"raw/{carpeta}/"
    blobs = gcs.list_blobs(BUCKET, prefix=prefix)
    particiones = {}
    for blob in blobs:
        partes = blob.name.split("/")
        if len(partes) == 4 and partes[2].isdigit() and blob.name.endswith(".csv"):
            fecha_str = partes[2]
            particiones[fecha_str] = f"gs://{BUCKET}/{blob.name}"
    return particiones


def cargar_transaccional(bq, gcs_uri, tabla, fecha_str):
    table_ref = f"{PROJECT}.{DATASET}.{tabla}${fecha_str}"
    job_config = LoadJobConfig(
        source_format=SourceFormat.CSV,
        skip_leading_rows=1,
        autodetect=True,
        write_disposition=WriteDisposition.WRITE_TRUNCATE,
        time_partitioning=TimePartitioning(type_=TimePartitioningType.DAY, field=None),
    )
    job = bq.load_table_from_uri(gcs_uri, table_ref, job_config=job_config)
    job.result()
    return job.output_rows


def cargar_maestro(bq, gcs_uri, tabla):
    table_ref = f"{PROJECT}.{DATASET}.{tabla}"
    job_config = LoadJobConfig(
        source_format=SourceFormat.CSV,
        skip_leading_rows=1,
        autodetect=True,
        write_disposition=WriteDisposition.WRITE_TRUNCATE,
    )
    job = bq.load_table_from_uri(gcs_uri, table_ref, job_config=job_config)
    job.result()

    bq.query(f"ALTER TABLE `{table_ref}` ADD COLUMN IF NOT EXISTS fecha_snapshot TIMESTAMP").result()
    bq.query(f"UPDATE `{table_ref}` SET fecha_snapshot = CURRENT_TIMESTAMP() WHERE fecha_snapshot IS NULL").result()

    return job.output_rows


def main():
    bq  = bigquery.Client(project=PROJECT)
    gcs = storage.Client(project=PROJECT)

    resumen = {"ok": 0, "error": 0, "omitido": 0}

    print("=== TRANSACCIONALES ===")
    for carpeta, _ in TRANSACCIONALES.items():
        particiones_gcs = listar_particiones_gcs(gcs, carpeta)
        if not particiones_gcs:
            print(f"  {carpeta}: sin archivos en GCS")
            continue

        procesadas = particiones_ya_procesadas(bq, carpeta)

        for fecha_str, gcs_uri in sorted(particiones_gcs.items()):
            # Convertir "20251231" a "2025-12-31" para comparar con la tabla de control
            fecha_iso = f"{fecha_str[:4]}-{fecha_str[4:6]}-{fecha_str[6:]}"
            if fecha_iso in procesadas:
                print(f"  {carpeta}/{fecha_str}: ya procesado, omitiendo")
                resumen["omitido"] += 1
                continue

            try:
                rows = cargar_transaccional(bq, gcs_uri, carpeta, fecha_str)
                registrar_control(
                    bq,
                    tabla_destino=carpeta,
                    archivo_origen=gcs_uri,
                    fecha_particion=fecha_iso,
                    tipo="INCREMENTAL",
                    estado="EXITOSO",
                    registros_cargados=rows,
                )
                print(f"  [OK] {carpeta}/{fecha_str} — {rows:,} registros")
                resumen["ok"] += 1
            except Exception as e:
                registrar_control(
                    bq,
                    tabla_destino=carpeta,
                    archivo_origen=gcs_uri,
                    fecha_particion=fecha_iso,
                    tipo="INCREMENTAL",
                    estado="ERROR",
                    mensaje_error=str(e),
                )
                print(f"  [ERROR] {carpeta}/{fecha_str} — {e}")
                resumen["error"] += 1

    print("\n=== MAESTROS ===")
    for carpeta, archivo in MAESTROS.items():
        gcs_uri = f"gs://{BUCKET}/raw/{carpeta}/{archivo}"
        try:
            rows = cargar_maestro(bq, gcs_uri, carpeta)
            registrar_control(
                bq,
                tabla_destino=carpeta,
                archivo_origen=gcs_uri,
                fecha_particion=None,
                tipo="SNAPSHOT",
                estado="EXITOSO",
                registros_cargados=rows,
            )
            print(f"  [OK] {carpeta} — {rows:,} registros")
            resumen["ok"] += 1
        except Exception as e:
            registrar_control(
                bq,
                tabla_destino=carpeta,
                archivo_origen=gcs_uri,
                fecha_particion=None,
                tipo="SNAPSHOT",
                estado="ERROR",
                mensaje_error=str(e),
            )
            print(f"  [ERROR] {carpeta} — {e}")
            resumen["error"] += 1

    print(f"\n=== RESUMEN ===")
    print(f"  Exitosos:  {resumen['ok']}")
    print(f"  Errores:   {resumen['error']}")
    print(f"  Omitidos:  {resumen['omitido']}")


if __name__ == "__main__":
    main()
