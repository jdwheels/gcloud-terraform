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
    github = {
      source  = "integrations/github"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "http" {}

resource "google_project_service" "gke" {
  service = "container.googleapis.com"
}

resource "google_project_service" "artifact" {
  service = "artifactregistry.googleapis.com"
}

resource "google_project_service" "dns" {
  service = "dns.googleapis.com"
}

resource "google_project_service" "servicenetworking" {
  service = "servicenetworking.googleapis.com"
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

resource "google_compute_global_address" "services" {
  name          = "primary-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "services" {
  service                 = "servicenetworking.googleapis.com"
  network                 = google_compute_network.vpc.name
  reserved_peering_ranges = [google_compute_global_address.services.name]
}

resource "google_service_account" "node_pool" {
  account_id   = "node-pool"
  display_name = "Node Pool"
}

locals {
  workload_pool      = "${var.project_id}.svc.id.goog"
  node_tags          = ["poo1-node"]
  kubernetes_version = var.kubernetes_version
}

data "google_container_engine_versions" "version" {
  version_prefix = "1.23."
}

resource "google_container_cluster" "primary" {
  depends_on = [
    google_project_service.gke
  ]
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
        display_name = cidr_blocks.key
        cidr_block   = cidr_blocks.value
      }
    }
  }
}

resource "google_container_node_pool" "pools" {
  for_each   = var.node_pools
  name       = each.key
  cluster    = google_container_cluster.primary.name
  node_count = each.value["count"]
  version    = local.kubernetes_version

  node_config {
    workload_metadata_config {
      mode = "GKE_METADATA" # seems enabled by default?
    }
    tags         = local.node_tags
    spot         = each.value["spot"]
    disk_size_gb = each.value["disk_size"]
    disk_type    = each.value["disk_type"]
    machine_type = each.value["type"]
    dynamic "taint" {
      for_each = each.value["taints"]
      content {
        key    = taint.value["key"]
        value  = taint.value["value"]
        effect = taint.value["effect"]
      }
    }
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}

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

resource "google_dns_managed_zone" "zone" {
  depends_on = [
    google_project_service.dns
  ]
  name     = var.zone_name
  dns_name = "${var.zone_name}.${var.root_domain}."
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

resource "google_compute_firewall" "default" {
  name      = "test-firewall"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports = [
      #      ingress-nginx
      "8443",
      #      istio:
      "10250",
      "443",
      "15017"
    ]
  }

  target_tags   = local.node_tags
  source_ranges = [google_container_cluster.primary.private_cluster_config[0].master_ipv4_cidr_block]
}


resource "kubernetes_role" "engineer" {
  depends_on = [google_container_node_pool.pools]
  metadata {
    name = "engineer"
  }
  rule {
    api_groups = ["", "apps", "networking.k8s.io"]
    resources = [
      "pods",
      "pods/attach",
      "deployments",
      "services",
      "configmaps",
      "ingresses"
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
  depends_on = [google_container_node_pool.pools]
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

module "ingress_nginx" {
  depends_on = [
    google_container_node_pool.pools,
    google_compute_router_nat.main,
    google_compute_firewall.default,
  ]
  source            = "./modules/ingress-nginx"
  authorized_blocks = var.authorized_blocks
}

module "cert_manager" {
  depends_on = [
    google_container_node_pool.pools,
    google_compute_router_nat.main
  ]
  source               = "./modules/cert-manager"
  google_project_id    = var.project_id
  workload_pool        = local.workload_pool
  namespace            = "cert-manager"
  serviceAccount       = "cert-manager"
  acme_account_email   = var.admin_user_email
  hosted_zone_name     = google_dns_managed_zone.zone.name
  dns_zone             = local.sub_domain
  http01_ingress_class = "nginx"
}

module "external_dns" {
  depends_on = [
    google_container_node_pool.pools,
    google_compute_router_nat.main
  ]
  source            = "./modules/external-dns"
  google_project_id = var.project_id
  workload_pool     = local.workload_pool
  namespace         = "external-dns"
  serviceAccount    = "external-dns"
  dns_zone          = local.sub_domain
}

module "registry" {
  depends_on = [
    google_project_service.artifact,
    google_compute_router_nat.main
  ]
  source                 = "./modules/registry"
  user_admins            = [var.admin_user_email]
  user_writers           = var.engineers
  serviceaccount_readers = [google_service_account.node_pool.email]
  registry_name          = var.docker_registry_name
  registry_description   = var.docker_registry_description
  location               = var.region
}

provider "github" {
  alias = "github_istio"
  owner = "istio"
}

module "istio" {
  depends_on = [
    google_container_node_pool.pools,
    google_compute_router_nat.main,
    google_compute_firewall.default
  ]
  source            = "./modules/istio"
  authorized_blocks = var.authorized_blocks
  providers = {
    github = github.github_istio
  }
  dns_zone = local.sub_domain
  enabled  = var.istio_enabled
}

resource "google_compute_address" "additional" {
  count = var.additional_static_ips
  name  = "gke-static-${count.index}"
}

module "storage" {
  source            = "./modules/storage"
  buckets           = var.buckets
  google_project_id = var.project_id
  workload_pool     = local.workload_pool
  region            = var.region
}

module "database" {
  source             = "./modules/database"
  authorized_blocks  = var.authorized_blocks
  region             = var.region
  database_instances = var.database_instances
  private_network    = google_compute_network.vpc.id
  service_account    = var.database_service_account
  project_id         = var.project_id
  workload_pool      = local.workload_pool
}
