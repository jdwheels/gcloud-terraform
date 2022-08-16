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
    })
  )
}

variable "additional_static_ips" {
  type = number
  default = 0
}
