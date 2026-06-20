from google.cloud import bigquery

client = bigquery.Client(project="sing1261")

print("Creando stored procedure...")
with open("etl_raw.sql", encoding="utf-8") as f:
    sql_create = f.read()
client.query(sql_create).result()

print("Ejecutando ETL...")
client.query("CALL `sing1261.ali1_raw.sp_etl_raw`()").result()

print("ETL completado. Revisa sing1261.ali1_raw.etl_control para el resultado.")
