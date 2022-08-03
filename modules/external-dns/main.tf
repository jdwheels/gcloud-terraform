resource "google_service_account" "external_dns" {
  account_id   = "sa-edns"
  display_name = "Kubernetes external-dns"
}

resource "google_project_iam_member" "external_dns" {
  member  = "serviceAccount:${google_service_account.external_dns.email}"
  project = var.google_project_id
  role    = "roles/dns.admin"
}

resource "google_service_account_iam_member" "external_dns" {
  member             = "serviceAccount:${var.workload_pool}[${var.namespace}/${var.serviceAccount}]"
  role               = "roles/iam.workloadIdentityUser"
  service_account_id = google_service_account.external_dns.id
}

resource "helm_release" "external_dns" {
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  name             = "external-dns"
  version          = "1.10.1"
  namespace        = var.namespace
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  recreate_pods    = true
  set {
    name  = "serviceAccount.name"
    value = var.serviceAccount
  }
  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = google_service_account.external_dns.email
  }
  set {
    name  = "provider"
    value = "google"
  }
  set {
    name  = "domainFilters"
    value = "{${var.dns_zone}}"
  }
  set {
    name  = "sources"
    value = "{ingress,istio-gateway}"
  }
  set {
    name  = "policy"
    value = "sync"
  }
  set_sensitive {
    name  = "extraArgs"
    value = "{--google-project=${var.google_project_id}}"
  }
}
