resource "google_sql_database_instance" "instances" {
  for_each         = var.database_instances
  name             = each.key
  database_version = each.value["version"]
  region           = var.region
  settings {
    disk_size = 50

    tier = each.value["tier"]
    backup_configuration {
      enabled = false
    }

    ip_configuration {
      ipv4_enabled    = true
      private_network = var.private_network
      require_ssl     = false
      dynamic "authorized_networks" {
        for_each = var.authorized_blocks
        content {
          name  = authorized_networks.key
          value = authorized_networks.value
        }
      }
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    maintenance_window {
      day  = 7
      hour = 4
    }
  }
}

module "service_account" {
  source = "../service-account"
  account_id = "gsa-${var.service_account}"
  create_service_account = false
  google_project_id = var.project_id
  workload_pool = var.workload_pool
  service_account = var.service_account
  namespace = "default"
}

resource "google_project_iam_member" "member" {
  member  = "serviceAccount:${module.service_account.email}"
  project = var.project_id
  role    = "roles/cloudsql.editor"
}

resource "google_sql_user" "app" {
  for_each = google_sql_database_instance.instances
  name     = trimsuffix(module.service_account.email, ".gserviceaccount.com")
  instance = each.value["name"]
  type = "CLOUD_IAM_SERVICE_ACCOUNT"
}