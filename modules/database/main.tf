data "google_compute_network" "primary" {
  name = "primary"
}

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
      private_network = data.google_compute_network.primary.id
      require_ssl     = false
      dynamic "authorized_networks" {
        for_each = var.authorized_blocks
        content {
          name  = authorized_networks.key
          value = authorized_networks.value
        }
      }
    }
    maintenance_window {
      day  = 7
      hour = 4
    }
  }
}
