terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 4.0"
    }
  }
}

locals {
  istio_repository = "https://istio-release.storage.googleapis.com/charts"
  istio_version    = "1.14.2"
}

resource "helm_release" "istio_base" {
  repository       = local.istio_repository
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  name             = "istio-base"
  version          = local.istio_version
  atomic           = true
  cleanup_on_fail  = true
}

resource "helm_release" "istiod" {
  depends_on = [
    helm_release.istio_base
  ]
  repository      = local.istio_repository
  chart           = "istiod"
  namespace       = "istio-system"
  name            = "istiod"
  version         = local.istio_version
  atomic          = true
  cleanup_on_fail = true
  recreate_pods = true
  set {
    name = "meshConfig.outboundTrafficPolicy.mode"
#    value = "ALLOW_ANY"
    value = "REGISTRY_ONLY"
  }
  set {
    name = "telemetry.v2.accessLogPolicy.enabled"
    value = "true"
  }
}

locals {
  addons = toset(["kiali", "prometheus", "jaeger", "grafana"])
}


data "github_repository" "istio" {
  full_name = "istio/istio"
}

data "http" "istio_addons" {
  for_each = local.addons
  url      = "https://raw.githubusercontent.com/istio/istio/${local.istio_version}/samples/addons/${each.value}.yaml"
}

#data "github_repository_file" "addons" {
#  for_each   = local.addons
#  file       = "samples/addons/${each.value}.yaml"
#  branch     = local.istio_version
#  repository = data.github_repository.istio.name
#}


data "kubectl_file_documents" "addons" {
  for_each = local.addons
  content  = data.http.istio_addons[each.value].body
}



locals {
  manifests = flatten([
    for addon in local.addons : [
      for id, content in data.kubectl_file_documents.addons[addon].manifests : {
        id      = id
        content = content
      }
    ]
  ])
}

#resource "kubectl_manifest" "addons" {
#  depends_on = [
#    helm_release.istiod,
#  ]
#  for_each = {
#    for manifest in local.manifests : manifest["id"] => manifest["content"]
#  }
#  yaml_body = each.value
#  lifecycle {
#    ignore_changes = [
#      yaml_incluster
#    ]
#  }
#}

resource "google_compute_address" "istio" {
  name = "istio"
}

resource "kubernetes_manifest" "cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "istio-wildcard-tls"
      namespace = "default"
    }
    spec = {
      secretName : "istio-wildcard-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      commonName = "*.istio.${var.dns_zone}"
      dnsNames = [
        "istio.${var.dns_zone}",
        "*.istio.${var.dns_zone}"
      ]
    }
  }
}

resource "helm_release" "default_gateway" {
  depends_on = [
    kubernetes_manifest.cert
  ]
  repository      = local.istio_repository
  chart           = "gateway"
  namespace       = "istio-system"
  name            = "istio-ingressgateway"
  version         = local.istio_version
  atomic          = true
  cleanup_on_fail = true
  set {
    name  = "service.loadBalancerIP"
    value = google_compute_address.istio.address
  }
  set {
    name  = "service.loadBalancerSourceRanges"
    value = "{${join(",", values(var.authorized_blocks))}}"
  }
}

resource "helm_release" "egress_gateway" {
  repository      = local.istio_repository
  chart           = "gateway"
  namespace       = "istio-system"
  name            = "istio-egressgateway"
  version         = local.istio_version
  atomic          = true
  cleanup_on_fail = true
  set {
    name  = "service.type"
    value = "ClusterIP"
  }
}
