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
}

locals {
  addons = toset(["kiali", "prometheus", "jaeger", "grafana"])
}


data "github_repository" "istio" {
  full_name = "istio/istio"
}

data "github_repository_file" "addons" {
  for_each   = local.addons
  file       = "samples/addons/${each.value}.yaml"
  branch     = "release-1.14"
  repository = data.github_repository.istio.name
}


data "kubectl_file_documents" "addons" {
  for_each = local.addons
  content  = data.github_repository_file.addons[each.value].content
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

resource "kubectl_manifest" "addons" {
  depends_on = [
    helm_release.istiod
  ]
  for_each = {
    for manifest in local.manifests : manifest["id"] => manifest["content"]
  }
  yaml_body = each.value
}
