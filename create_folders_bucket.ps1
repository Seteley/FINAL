$bucket = "gs://ali1_bucket"
$folders = @("raw", "trusted", "curated", "predictive")

foreach ($folder in $folders) {
    gcloud storage cp - "$bucket/$folder/.keep" --content-type="text/plain" 2>&1 | Out-Null
    Write-Host "Carpeta creada: $folder/"
}

Write-Host "Listo."
