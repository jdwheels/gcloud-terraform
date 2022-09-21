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
  count = var.service_account == "" ? 0 : 1
  source                 = "../service-account"
  account_id             = "gsa-${var.service_account}"
  create_service_account = false
  google_project_id      = var.project_id
  workload_pool          = var.workload_pool
  service_account        = var.service_account
  namespace              = "default"
}

resource "google_project_iam_member" "member" {
  count = var.service_account == "" ? 0 : 1
  member  = "serviceAccount:${module.service_account[count.index].email}"
  project = var.project_id
  role    = "roles/cloudsql.editor"
}

resource "google_sql_user" "app" {
  for_each = google_sql_database_instance.instances
  name     = trimsuffix(module.service_account[0].email, ".gserviceaccount.com")
  instance = each.value["name"]
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

#resource "google_sql_user" "admins" {
#  for_each = { for x in var.database_instances : x  }
#  instance = google_sql_database_instance[]
#  name     = ""
#}

resource "null_resource" "x" {
  for_each = local.db_users_map
  provisioner "local-exec" {
    command = "docker run --rm -e PGPASSWORD postgres psql -h ${google_sql_database_instance.instances[each.value["instance"]].public_ip_address} -U ${each.value["user"]} --dbname postgres -c 'SELECT 1'"
    environment = {
      PGPASSWORD = random_password.admins[each.key].result
    }
  }
}

locals {
  db_users = flatten([
    for x in keys(var.database_instances) : [
      for u in var.database_instances[x].users : {
        user     = u,
        instance = x
      }
    ]
  ])
  db_users_map = { for x in local.db_users : join("_", [x["instance"], x["user"]]) => x }
}

resource "random_password" "admins" {
  for_each = local.db_users_map
  length   = 16
}

resource "google_sql_user" "admins" {
  for_each = local.db_users_map
  instance = each.value["instance"]
  name     = each.value["user"]
  password = random_password.admins[each.key].result
}

output "o" {
  value = local.db_users_map
}
