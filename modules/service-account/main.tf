resource "google_service_account" "gsa" {
  account_id = var.account_id
}

resource "google_service_account_iam_member" "gsa_ksa" {
  member             = "serviceAccount:${var.workload_pool}[${var.namespace}/${var.service_account}]"
  role               = "roles/iam.workloadIdentityUser"
  service_account_id = google_service_account.gsa.id
}

resource "kubernetes_service_account" "ksa" {
  count = var.create_service_account ? 1 : 0
  metadata {
    name = var.service_account
    namespace = var.namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.gsa.email
    }
  }
}
