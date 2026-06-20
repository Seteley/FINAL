from google.cloud import storage

client = storage.Client(project="sing1261")
bucket = client.bucket("ali1_bucket")

transaccionales = [
    "ventas",
    "pedidos",
    "devoluciones",
    "fill_rate",
    "inventario",
    "metas",
    "promociones",
    "inversion_promocional",
]

maestros = [
    "clientes",
    "productos",
    "canal",
    "geografia",
    "almacen",
    "vendedor",
]

for carpeta in transaccionales + maestros:
    blob = bucket.blob(f"raw/{carpeta}/.keep")
    blob.upload_from_string("")
    print(f"Creada: raw/{carpeta}/")

print("Listo.")
