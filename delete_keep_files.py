from google.cloud import storage

client = storage.Client(project="sing1261")
blobs = client.list_blobs("ali1_bucket", prefix="raw/")

eliminados = 0
for blob in blobs:
    if blob.name.endswith(".keep"):
        blob.delete()
        print(f"Eliminado: {blob.name}")
        eliminados += 1

print(f"\nTotal eliminados: {eliminados}")
