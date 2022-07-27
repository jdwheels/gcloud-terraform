resource "google_compute_address" "nginx" {
  name = "xyz"
}

resource "helm_release" "ingress_nginx" {
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.2.0"
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  #  timeout          = 120
  set {
    name  = "controller.service.loadBalancerIP"
    value = google_compute_address.nginx.address
  }
  set {
    name  = "controller.service.loadBalancerSourceRanges"
    value = "{${join(",", values(var.authorized_blocks))}}"
  }
}
