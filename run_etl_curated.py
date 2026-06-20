from google.cloud import bigquery

client = bigquery.Client(project="sing1261")

print("Creando stored procedure curated...")
with open("etl_curated.sql", encoding="utf-8") as f:
    sql = f.read()
client.query(sql).result()

print("Ejecutando ETL curated...")
client.query("CALL `sing1261.ali1_curated.sp_etl_curated`()").result()

print("ETL curated completado. Revisa sing1261.ali1_curated.etl_control para el resultado.")
