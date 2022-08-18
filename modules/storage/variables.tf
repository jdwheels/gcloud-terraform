variable "buckets" {
  type = map(object({}))
}

variable "google_project_id" {
  type = string
}

variable "workload_pool" {
  type = string
}
