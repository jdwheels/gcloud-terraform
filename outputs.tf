output "url" {
  value = [for x in values(local.ingress_host_mapping) : "https://${x}"]
}
output "zone_dns" {
  value = google_dns_managed_zone.zone.dns_name
}
output "zone_name_servers" {
  value = google_dns_managed_zone.zone.name_servers
}
