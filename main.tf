terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-c"
}

resource "google_compute_network" "vpc" {
  name                    = "primary"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "net" {
  ip_cidr_range = "192.168.0.0/20"
  name          = "net-1"
  network       = google_compute_network.vpc.name
  secondary_ip_range {
    ip_cidr_range = "10.4.0.0/14"
    range_name    = "pods"
  }
  secondary_ip_range {
    ip_cidr_range = "10.0.32.0/20"
    range_name    = "services"
  }
  private_ip_google_access = true
}

data "google_project" "default" {
  project_id = var.project_id
}

resource "google_service_account" "node_pool" {
  account_id   = "node-pool"
  display_name = "Node Pool"
}

resource "google_service_account" "external_dns" {
  account_id   = "sa-edns"
  display_name = "Kubernetes external-dns"
}

resource "google_service_account" "dns01_solver" {
  account_id = "dns01-solver"
}

locals {
  workload_pool      = "${data.google_project.default.project_id}.svc.id.goog"
  node_tags          = ["poo1-node"]
  kubernetes_version = "1.23.5-gke.1503"
}

data "google_container_engine_versions" "version" {
  version_prefix = "1.23."
}

resource "google_container_cluster" "primary" {
  name                     = "primary"
  subnetwork               = google_compute_subnetwork.net.name
  initial_node_count       = 1
  remove_default_node_pool = true
  network                  = google_compute_network.vpc.name
  networking_mode          = "VPC_NATIVE"
  min_master_version       = local.kubernetes_version

  workload_identity_config {
    workload_pool = local.workload_pool
  }
  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.net.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.net.secondary_ip_range[1].range_name
  }
  private_cluster_config {
    enable_private_endpoint = false
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "172.16.0.32/28"
  }
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_blocks
      content {
        cidr_block = cidr_blocks.value
      }
    }
  }
}

resource "google_container_node_pool" "pool1" {
  name       = "pool1"
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count
  version    = local.kubernetes_version

  node_config {
    workload_metadata_config {
      mode = "GKE_METADATA" # seems enabled by default?
    }
    tags            = local.node_tags
    preemptible     = true
    machine_type    = "e2-standard-4"
    service_account = google_service_account.node_pool.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}

#data "google_compute_instance_group" "instance_groups" {
#  for_each  = toset(google_container_node_pool.pool1.instance_group_urls)
#  self_link = each.value
#}

#data "google_compute_instance_template" "template" {
#  for_each = toset(values(data.google_compute_instance_group.instance_groups)[*].name)
#  project = data.google_project.default.project_id
#  name = trimsuffix(each.value, "-grp")
#}

#data "google_compute_instance" "instances" {
#  for_each  = toset(flatten(values(data.google_compute_instance_group.instance_groups)[*].instances))
#  self_link = each.value
#}

data "google_client_config" "provider" {}

locals {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "kubernetes" {
  host                   = local.host
  token                  = local.token
  cluster_ca_certificate = local.cluster_ca_certificate
}

provider "kubectl" {
  host                   = local.host
  token                  = local.token
  cluster_ca_certificate = local.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = local.host
    token                  = local.token
    cluster_ca_certificate = local.cluster_ca_certificate
  }
}

locals {
  cert_manager_serviceAccount = "cert-manager"
  cert_manager_namespace      = "cert-manager"
  external_dns_serviceAccount = "external-dns"
  external_dns_namespace      = "external-dns"
}

resource "google_project_iam_member" "dns01_solver" {
  member  = "serviceAccount:${google_service_account.dns01_solver.email}"
  project = data.google_project.default.project_id
  role    = "roles/dns.admin"
}

resource "google_project_iam_member" "external_dns" {
  member  = "serviceAccount:${google_service_account.external_dns.email}"
  project = data.google_project.default.project_id
  role    = "roles/dns.admin"
}

resource "google_service_account_iam_member" "dns01_solver" {
  member             = "serviceAccount:${local.workload_pool}[${local.cert_manager_namespace}/${local.cert_manager_serviceAccount}]"
  role               = "roles/iam.workloadIdentityUser"
  service_account_id = google_service_account.dns01_solver.id
}

resource "google_service_account_iam_member" "external_dns" {
  member             = "serviceAccount:${local.workload_pool}[${local.external_dns_namespace}/${local.external_dns_serviceAccount}]"
  role               = "roles/iam.workloadIdentityUser"
  service_account_id = google_service_account.external_dns.id
}

resource "google_compute_address" "nginx" {
  name = "xyz"
}

resource "google_artifact_registry_repository" "demo" {
  #  location      = "us-central1"
  repository_id = "my-repository"
  description   = "example docker repository"
  format        = "DOCKER"
}

resource "google_artifact_registry_repository_iam_binding" "admin" {
  project    = google_artifact_registry_repository.demo.project
  location   = google_artifact_registry_repository.demo.location
  repository = google_artifact_registry_repository.demo.name
  role       = "roles/artifactregistry.admin"
  members = [
    "user:${var.admin_user_email}"
  ]
}

resource "google_artifact_registry_repository_iam_binding" "reader" {
  project    = google_artifact_registry_repository.demo.project
  location   = google_artifact_registry_repository.demo.location
  repository = google_artifact_registry_repository.demo.name
  role       = "roles/artifactregistry.reader"
  members = [
    "serviceAccount:${google_service_account.node_pool.email}",
  ]
}

resource "google_dns_managed_zone" "zone" {
  name     = "z1"
  dns_name = "z1.${var.root_domain}."
}

resource "google_compute_router" "main" {
  name    = "main"
  network = google_compute_network.vpc.name
  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "main" {
  name   = "${google_compute_network.vpc.name}-nat"
  router = google_compute_router.main.name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.net.name
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "helm_release" "ingress_nginx" {
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.2.0"
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  #  timeout          = 120
  set {
    name  = "controller.service.loadBalancerIP"
    value = google_compute_address.nginx.address
  }
  set {
    name  = "controller.service.loadBalancerSourceRanges"
    value = "{${join(",", values(var.authorized_blocks))}}"
  }
}

resource "helm_release" "cert_manager" {
  depends_on = [
    google_service_account_iam_member.dns01_solver
  ]
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.9.0"
  name             = "cert-manager"
  namespace        = local.cert_manager_namespace
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
    value = local.cert_manager_serviceAccount
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

resource "helm_release" "external_dns" {
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  name             = "external-dns"
  version          = "1.10.1"
  namespace        = local.external_dns_namespace
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  set {
    name  = "serviceAccount.name"
    value = local.external_dns_serviceAccount
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
    value = "{${trimsuffix(google_dns_managed_zone.zone.dns_name, ".")}}"
  }
  set {
    name  = "sources"
    value = "{ingress}"
  }
  set {
    name  = "policy"
    value = "sync"
  }
  set_sensitive {
    name  = "extraArgs"
    value = "{--google-project=${data.google_project.default.project_id}}"
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
        email  = var.admin_user_email
        privateKeySecretRef = {
          name = each.key
        }
        solvers = [
          {
            dns01 = {
              cloudDNS = {
                project        = data.google_project.default.project_id
                hostedZoneName = google_dns_managed_zone.zone.name
              }
            }
            selector = {
              dnsZones = [
                local.sub_domain
              ]
            }
          },
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  })
}

resource "kubernetes_role" "engineer" {
  metadata {
    name = "engineer"
  }
  rule {
    api_groups = ["", "apps"]
    resources = [
      "pods",
      "pods/attach",
      "deployments",
      "services",
      "configmaps"
    ]
    verbs = [
      "get",
      "watch",
      "list",
      "update",
      "create",
      "delete",
      "patch"
    ]
  }
}

resource "kubernetes_role_binding" "engineer" {
  metadata {
    name = "engineer"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.engineer.metadata[0].name
  }
  dynamic "subject" {
    for_each = var.engineers
    content {
      kind = "User"
      name = subject.value
    }
  }
}

locals {
  sub_domain           = trimsuffix(google_dns_managed_zone.zone.dns_name, ".")
  ingress_names        = var.ingress_names
  ingress_host_mapping = { for n in local.ingress_names : n => "${n}.${local.sub_domain}" }
}


#resource "kubectl_manifest" "managed_cert" {
#  yaml_body = yamlencode({
#    apiVersion = "networking.gke.io/v1"
#    kind       = "ManagedCertificate"
#    metadata = {
#      name = "x-managed-cert"
#    }
#    spec = {
#      domains = [
#        local.ingress_host_x
#      ]
#    }
#  })
#}
#
resource "kubernetes_deployment" "nginx" {
  metadata {
    name = "xyz"
  }
  spec {
    selector {
      match_labels = {
        app = "xyz"
      }
    }
    template {
      metadata {
        labels = {
          app : "xyz"
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx"
          port {
            container_port = 80
            name           = "http"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "nginx" {
  metadata {
    name = "xyz"
    annotations = {
      "cloud.google.com/neg" : "{\"ingress\": true}"
    }
  }
  spec {
    selector = {
      app = kubernetes_deployment.nginx.spec[0].template[0].metadata[0].labels.app
    }
    port {
      port        = 80
      target_port = "http"
    }
    type = "ClusterIP"
  }
  lifecycle {
    //noinspection HILUnresolvedReference
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

locals {
  #  node_pool_tags = setunion(values(data.google_compute_instance.instances)[*].tags...)
  #  node_pool_tags = flatten(values(data.google_compute_instance_template.template)[*].tags)

}

resource "google_compute_firewall" "default" {
  name      = "test-firewall"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["8443"]
  }

  target_tags   = google_container_node_pool.pool1.node_config[0].tags
  source_ranges = [google_container_cluster.primary.private_cluster_config[0].master_ipv4_cidr_block]
}

resource "kubernetes_ingress_v1" "nginx" {
  for_each = local.ingress_host_mapping
  metadata {
    name = each.key
    annotations = {
      "cert-manager.io/cluster-issuer" : "letsencrypt-staging"
      #      "cert-manager.io/cluster-issuer": "letsencrypt-prod"
      "external-dns.alpha.kubernetes.io/ttl" : "1m"
      #      "kubernetes.io/ingress.global-static-ip-name" : google_compute_global_address.nginx.name
      #      "networking.gke.io/managed-certificates" : kubectl_manifest.managed_cert.name
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts = [
        each.value
      ]
      secret_name = "${each.key}-tls"
    }
    rule {
      host = each.value
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.nginx.metadata[0].name
              port {
                number = kubernetes_service.nginx.spec[0].port[0].port
              }
            }
          }
        }
      }
    }
  }
}
