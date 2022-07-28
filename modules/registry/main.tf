resource "google_artifact_registry_repository" "demo" {
  location      = var.location
  repository_id = var.registry_name
  description   = var.registry_description
  format        = var.registry_format
}

resource "google_artifact_registry_repository_iam_binding" "admin" {
  location   = google_artifact_registry_repository.demo.location
  repository = google_artifact_registry_repository.demo.name
  role       = "roles/artifactregistry.admin"
  members    = [for u in var.user_admins : "user:${u}"]
}

resource "google_artifact_registry_repository_iam_binding" "writer" {
  location   = google_artifact_registry_repository.demo.location
  repository = google_artifact_registry_repository.demo.name
  role       = "roles/artifactregistry.writer"
  members    = [for u in var.user_writers : "user:${u}"]
}

resource "google_artifact_registry_repository_iam_binding" "reader" {
  location   = google_artifact_registry_repository.demo.location
  repository = google_artifact_registry_repository.demo.name
  role       = "roles/artifactregistry.reader"
  members    = [for s in var.serviceaccount_readers : "serviceAccount:${s}"]
}
