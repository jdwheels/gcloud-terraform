resource "google_storage_bucket" "buckets" {
  for_each = var.buckets
  location = "US"
  name     = each.key
  force_destroy = true
  storage_class = "REGIONAL"
}

module "service_accounts" {
  for_each = var.buckets
  source = "../service-account"
  google_project_id = var.google_project_id
  account_id = "storage-${each.key}-gsa"
  namespace = "default"
  service_account = "storage-${each.key}"
  workload_pool = var.workload_pool
}

resource "google_storage_bucket_iam_member" "member" {
  for_each = var.buckets
  bucket = google_storage_bucket.buckets[each.key].name
  role = "roles/storage.admin"
  member = "serviceAccount:${module.service_accounts[each.key].email}"
}
