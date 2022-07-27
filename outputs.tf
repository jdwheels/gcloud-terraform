output "url" {
  value = [for x in values(local.ingress_host_mapping) : "https://${x}"]
}
