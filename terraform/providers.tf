terraform {
  required_version = ">= 1.5"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }
}

# Points at the local `kind` cluster's own kubeconfig context. No cloud
# credentials, no remote state backend -- this is a local lab, not a
# production account.
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-network-lab"
}
