# Second ArgoCD Application, alongside application.tf's monitoring stack,
# registering k8s-slurm/'s Slurm simulated-GPU demo. Deliberately excludes
# the slurm-munge-key Secret -- that is created out-of-band by
# scripts/deploy-k8s-slurm.sh, never committed to git, so ArgoCD only ever
# syncs the ConfigMap/Deployment/Service manifests in k8s-slurm/.
resource "kubernetes_manifest" "network_lab_slurm" {
  depends_on = [null_resource.argocd_install]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "network-lab-slurm"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/williamhuang1261/network-lab.git"
        targetRevision = "HEAD"
        path           = "k8s-slurm"
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
