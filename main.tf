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

module "ingress_nginx" {
  source            = "./modules/ingress-nginx"
  authorized_blocks = var.authorized_blocks
}

module "cert_manager" {
  source               = "./modules/cert-manager"
  google_project_id    = data.google_project.default.project_id
  workload_pool        = local.workload_pool
  namespace            = "cert-manager"
  serviceAccount       = "cert-manager"
  acme_account_email   = var.admin_user_email
  hosted_zone_name     = google_dns_managed_zone.zone.name
  dns_zone             = local.sub_domain
  http01_ingress_class = "nginx"
}

module "external_dns" {
  source            = "./modules/external-dns"
  google_project_id = data.google_project.default.project_id
  workload_pool     = local.workload_pool
  namespace         = "external-dns"
  serviceAccount    = "external-dns"
  dns_zone          = local.sub_domain
}

module "registry" {
  source                 = "./modules/registry"
  user_admins            = [var.admin_user_email]
  user_writers           = var.engineers
  serviceaccount_readers = [google_service_account.node_pool.email]
  registry_name          = "my-repository"
  registry_description   = "example docker repository"
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

resource "kubernetes_role" "engineer" {
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
