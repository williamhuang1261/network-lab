#!/bin/bash
# Deploys the Slurm simulated-GPU demo (slurm/) onto the same kind cluster
# the monitoring stack already runs on. Generates a fresh munge key locally
# (never committed -- see docs/slurm.md) and loads it as a Kubernetes
# Secret, builds the controller/compute images if needed, loads them into
# kind, then applies k8s-slurm/.
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER_NAME="${KIND_CLUSTER_NAME:-network-lab}"

echo "==> generating a fresh munge key (not committed to git)"
TMP_KEY_DIR="$(mktemp -d)"
docker run --rm -v "$TMP_KEY_DIR:/out" ubuntu:22.04 bash -c \
    "apt-get update -qq >/dev/null && apt-get install -y -qq munge >/dev/null 2>&1 && \
     /usr/sbin/mungekey -f -c -k /out/munge.key"

kubectl create secret generic slurm-munge-key \
    --namespace network-lab \
    --from-file=munge.key="$TMP_KEY_DIR/munge.key" \
    --dry-run=client -o yaml | kubectl apply -f -
rm -rf "$TMP_KEY_DIR"

echo "==> building controller/compute images"
docker build -t network-lab-slurmctld:latest -f slurm/docker/controller.Dockerfile slurm
docker build -t network-lab-slurmd-compute:latest -f slurm/docker/compute.Dockerfile slurm

echo "==> loading images into kind cluster $CLUSTER_NAME"
kind load docker-image network-lab-slurmctld:latest --name "$CLUSTER_NAME"
kind load docker-image network-lab-slurmd-compute:latest --name "$CLUSTER_NAME"

echo "==> applying manifests"
kubectl apply -f k8s-slurm/configmap.yaml
kubectl apply -f k8s-slurm/mariadb.yaml
kubectl apply -f k8s-slurm/slurmctld.yaml
kubectl apply -f k8s-slurm/slurmd-compute.yaml

echo "==> done. Check rollout with:"
echo "    kubectl -n network-lab get pods -l 'app in (mariadb,slurmctld,slurmd-compute)'"
