from google.cloud import bigquery

PROJECT = "sing1261"
DATASET = "ali1_raw"
TABLE   = "etl_control"

client = bigquery.Client(project=PROJECT)

schema = [
    bigquery.SchemaField("tabla_destino",      "STRING",    mode="REQUIRED"),
    bigquery.SchemaField("archivo_origen",     "STRING",    mode="REQUIRED"),
    bigquery.SchemaField("fecha_particion",    "DATE",      mode="NULLABLE"),
    bigquery.SchemaField("tipo",               "STRING",    mode="REQUIRED"),
    bigquery.SchemaField("estado",             "STRING",    mode="REQUIRED"),
    bigquery.SchemaField("registros_cargados", "INTEGER",   mode="NULLABLE"),
    bigquery.SchemaField("mensaje_error",      "STRING",    mode="NULLABLE"),
    bigquery.SchemaField("fecha_carga",        "TIMESTAMP", mode="REQUIRED"),
]

table_ref = f"{PROJECT}.{DATASET}.{TABLE}"
table = bigquery.Table(table_ref, schema=schema)
table = client.create_table(table, exists_ok=True)

print(f"Tabla de control lista: {table_ref}")
