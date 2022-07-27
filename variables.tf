variable "admin_user_email" {
  type      = string
  sensitive = true
}

variable "project_id" {
  type      = string
  sensitive = true
}

variable "root_domain" {
  type = string
}

variable "node_count" {
  type = number
}

variable "ingress_names" {
  type = set(string)
}

variable "authorized_blocks" {
  type = map(string)
}

variable "engineers" {
  type = set(string)
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "machine_type" {
  type = string
}

variable "docker_registry_name" {
  type = string
}

variable "docker_registry_description" {
  type = string
}

variable "zone_name" {
  type = string
}
