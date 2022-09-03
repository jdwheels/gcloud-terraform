variable "google_project_id" {
  type = string
}

variable "account_id" {
  type = string
}

#variable "role" {
#  type = string
#}

variable "workload_pool" {
  type = string
}

variable "namespace" {
  type    = string
  default = "default"
}

variable "service_account" {
  type = string
}

variable "create_service_account" {
  type    = bool
  default = true
}
