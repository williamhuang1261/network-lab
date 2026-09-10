# Replaces the manual `kubectl apply -f k8s/namespace.yaml` step from
# Extension C's README (see ../k8s/README.md, now superseded by this file
# and application.tf).
resource "kubernetes_namespace" "network_lab" {
  metadata {
    name = "network-lab"
  }
}
