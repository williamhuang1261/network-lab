#!/usr/bin/env bash
# Applies ArgoCD's official install manifest and blocks until argocd-server
# is actually serving, not just scheduled. Run by Terraform's null_resource
# local-exec provisioner in argocd.tf -- see docs/gitops.md for why this step
# is a shell script rather than typed Terraform resources.
set -euo pipefail

NAMESPACE="argocd"
MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

echo "Applying ArgoCD install manifest into namespace ${NAMESPACE}..."
# --server-side: ArgoCD's applicationsets.argoproj.io CRD exceeds the 256KiB
# limit on the client-side kubectl.kubernetes.io/last-applied-configuration
# annotation ("metadata.annotations: Too long"). Server-side apply tracks
# field ownership instead of that annotation, so it has no such limit.
kubectl apply --server-side --force-conflicts -n "${NAMESPACE}" -f "${MANIFEST_URL}"

echo "Waiting for argocd-server rollout..."
kubectl -n "${NAMESPACE}" rollout status deployment/argocd-server --timeout=300s

echo "Waiting for argocd-repo-server rollout..."
kubectl -n "${NAMESPACE}" rollout status deployment/argocd-repo-server --timeout=300s

echo "Waiting for argocd-application-controller statefulset..."
kubectl -n "${NAMESPACE}" rollout status statefulset/argocd-application-controller --timeout=300s

echo "ArgoCD is up."
