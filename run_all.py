from google.cloud import bigquery

client = bigquery.Client(project="sing1261")
datasets = ["ali1_raw", "ali1_trusted", "ali1_curated", "ali1_kpi", "ali1_predictive"]

# 1. Borrar y recrear todos los datasets
print("=== Reiniciando datasets ===")
for ds in datasets:
    client.delete_dataset(f"sing1261.{ds}", delete_contents=True, not_found_ok=True)
    print(f"  Eliminado: {ds}")
    dataset = bigquery.Dataset(f"sing1261.{ds}")
    dataset.location = "US"
    client.create_dataset(dataset)
    print(f"  Creado:    {ds}")

# 2. Ejecutar los 4 ETLs en secuencia
etls = [
    ("etl_raw.sql",        "CALL `sing1261.ali1_raw.sp_etl_raw`()",                    600),
    ("etl_trusted.sql",    "CALL `sing1261.ali1_trusted.sp_etl_trusted`()",            300),
    ("etl_curated.sql",    "CALL `sing1261.ali1_curated.sp_etl_curated`()",            300),
    ("sql/etl_kpi.sql",    "CALL `sing1261.ali1_kpi.sp_etl_kpi`()",                   300),
    ("etl_predictive.sql", "CALL `sing1261.ali1_predictive.sp_etl_predictive`()",     1800),
]

for sql_file, call_stmt, timeout in etls:
    print(f"\n=== {sql_file} ===")
    with open(sql_file, encoding="utf-8") as f:
        client.query(f.read()).result()
    print(f"  Procedure creado.")
    client.query(call_stmt).result(timeout=timeout)
    print(f"  ETL ejecutado.")

print("\nPipeline completo.")
