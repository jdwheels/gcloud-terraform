variable "registry_name" {
  type = string
}

variable "registry_description" {
  type = string
}

variable "registry_format" {
  type    = string
  default = "DOCKER"
}

variable "serviceaccount_readers" {
  type = set(string)
}

variable "user_writers" {
  type = set(string)
}

variable "user_admins" {
  type = set(string)
}
