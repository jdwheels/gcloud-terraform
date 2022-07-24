output "ip" {
  value = google_compute_address.nginx.address
}

output "url" {
  value = [for x in values(local.ingress_host_mapping) : "https://${x}"]
}
