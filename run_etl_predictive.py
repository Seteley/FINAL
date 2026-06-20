from google.cloud import bigquery

client = bigquery.Client(project="sing1261")

print("Creando stored procedure predictive...")
with open("etl_predictive.sql", encoding="utf-8") as f:
    sql = f.read()
client.query(sql).result()

print("Ejecutando ETL predictive (entrenamiento puede tomar varios minutos)...")
job = client.query("CALL `sing1261.ali1_predictive.sp_etl_predictive`()")
job.result(timeout=1800)

print("ETL predictive completado. Revisa sing1261.ali1_predictive.etl_control.")
