# ArgoCD's own namespace, separate from network-lab's.
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# ArgoCD's upstream install manifest is several thousand lines spanning CRDs,
# ClusterRoles, Deployments, StatefulSets and Services -- not a shape that
# gains anything from being hand-transcribed into typed `kubernetes_manifest`
# blocks. Terraform still owns *when* it runs (after the namespace exists,
# before application.tf's Application CR) and blocks apply until it is
# actually healthy, via scripts/wait-for-rollout.sh. See docs/gitops.md for
# the full trade-off writeup.
resource "null_resource" "argocd_install" {
  depends_on = [kubernetes_namespace.argocd]

  triggers = {
    # Re-run if the install script itself changes.
    script_hash = filesha256("${path.module}/scripts/wait-for-rollout.sh")
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/wait-for-rollout.sh"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found=true"
  }
}
