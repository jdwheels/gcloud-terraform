terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.0"
    }
  }
}

resource "google_service_account" "dns01_solver" {
  account_id = "dns01-solver"
}

resource "google_project_iam_member" "dns01_solver" {
  member  = "serviceAccount:${google_service_account.dns01_solver.email}"
  project = var.google_project_id
  role    = "roles/dns.admin"
}

resource "google_service_account_iam_member" "dns01_solver" {
  member             = "serviceAccount:${var.workload_pool}[${var.namespace}/${var.serviceAccount}]"
  role               = "roles/iam.workloadIdentityUser"
  service_account_id = google_service_account.dns01_solver.id
}

resource "helm_release" "cert_manager" {
  depends_on = [
    google_service_account_iam_member.dns01_solver
  ]
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.9.1"
  name             = "cert-manager"
  namespace        = var.namespace
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  recreate_pods    = true
  set {
    name  = "installCRDs"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = var.serviceAccount
  }
  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = google_service_account.dns01_solver.email
  }
  set {
    name  = "extraArgs"
    value = "{--enable-certificate-owner-ref=true}"
  }
}

locals {
  cluster_issuers = {
    letsencrypt-staging = "https://acme-staging-v02.api.letsencrypt.org/directory"
    letsencrypt-prod    = "https://acme-v02.api.letsencrypt.org/directory"
  }
}

resource "kubectl_manifest" "cluster_issuers" {
  for_each = local.cluster_issuers
  depends_on = [
    helm_release.cert_manager
  ]
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name      = each.key
      namespace = "cert-manager"
    }
    spec = {
      acme = {
        server = each.value
        email  = var.acme_account_email
        privateKeySecretRef = {
          name = each.key
        }
        solvers = [
          {
            dns01 = {
              cloudDNS = {
                project        = var.google_project_id
                hostedZoneName = var.hosted_zone_name
              }
            }
            selector = {
              dnsZones = [
                var.dns_zone
              ]
            }
          },
          {
            http01 = {
              ingress = {
                class = var.http01_ingress_class
              }
            }
          }
        ]
      }
    }
  })
}
