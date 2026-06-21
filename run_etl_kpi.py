from google.cloud import bigquery

client = bigquery.Client(project="sing1261")

print("Creando stored procedure KPI...")
with open("sql/etl_kpi.sql", encoding="utf-8") as f:
    client.query(f.read()).result()

print("Ejecutando ETL KPI...")
client.query("CALL `sing1261.ali1_kpi.sp_etl_kpi`()").result(timeout=300)

print("ETL KPI completado. Revisa sing1261.ali1_kpi.etl_control para el resultado.")
