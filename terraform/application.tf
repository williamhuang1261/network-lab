# Registers k8s/'s existing Deployment/Service/ConfigMap manifests as an
# ArgoCD-managed Application, replacing the manual `kubectl apply -f k8s/`
# step from Extension C's README. Only possible once null_resource.argocd_install
# has registered the Application CRD -- see docs/gitops.md for why this is a
# separate resource rather than folded into argocd.tf's single apply.
resource "kubernetes_manifest" "network_lab_monitoring" {
  depends_on = [null_resource.argocd_install]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "network-lab-monitoring"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        # Public repo; ArgoCD's default anonymous repo-server access is
        # enough over HTTPS, no repo credentials to manage.
        repoURL        = "https://github.com/williamhuang1261/network-lab.git"
        targetRevision = "HEAD"
        path           = "k8s"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "network-lab"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=false"] # namespace.tf already owns it
      }
    }
  }
}
