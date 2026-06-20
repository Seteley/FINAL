from google.cloud import bigquery

client = bigquery.Client(project="sing1261")

print("Creando stored procedure trusted...")
with open("etl_trusted.sql", encoding="utf-8") as f:
    sql = f.read()
client.query(sql).result()

print("Ejecutando ETL trusted...")
client.query("CALL `sing1261.ali1_trusted.sp_etl_trusted`()").result()

print("ETL trusted completado. Revisa sing1261.ali1_trusted.etl_control para el resultado.")
