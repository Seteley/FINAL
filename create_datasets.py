from google.cloud import bigquery

client = bigquery.Client(project="sing1261")

datasets = ["ali1_raw", "ali1_trusted", "ali1_curated", "ali1_analytics"]

for name in datasets:
    dataset_id = f"sing1261.{name}"
    dataset = bigquery.Dataset(dataset_id)
    dataset.location = "US"
    dataset = client.create_dataset(dataset, exists_ok=True)
    print(f"Creado: {dataset.dataset_id}")

print("Listo.")
