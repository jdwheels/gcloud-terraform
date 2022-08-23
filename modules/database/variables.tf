variable "region" {
  type = string
}

variable "authorized_blocks" {
  type = map(string)
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

variable "private_network" {
  type = string
}