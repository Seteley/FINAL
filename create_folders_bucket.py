from google.cloud import storage

client = storage.Client(project="sing1261")
bucket = client.bucket("ali1_bucket")

folders = ["raw", "trusted", "curated", "predictive"]

for folder in folders:
    blob = bucket.blob(f"{folder}/.keep")
    blob.upload_from_string("")
    print(f"Carpeta creada: {folder}/")

print("Listo.")
