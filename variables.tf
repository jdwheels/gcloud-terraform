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

variable "docker_registry_name" {
  type = string
}

variable "docker_registry_description" {
  type = string
}

variable "zone_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "istio_enabled" {
  type = bool
}

variable "node_pools" {
  type = map(
    object({
      count     = number
      disk_size = number
      disk_type = string
      spot      = bool
      type      = string
      taints = list(object({
        key    = string
        value  = string
        effect = string
      }))
      gpus = list(object({
        type  = string
        count = number
      }))
    })
  )
}

variable "additional_static_ips" {
  type    = number
  default = 0
}

variable "buckets" {
  type = map(object({}))
}

variable "database_instances" {
  type = map(
    object({
      version = string
      users   = list(string)
      tier    = string
    })
  )
}

variable "database_service_account" {
  type = string
}
