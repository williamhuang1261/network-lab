# Kubernetes manifests -- monitoring stack

Deploys Prometheus, Grafana and snmp-exporter -- the single-network subset of
the Docker Compose stack -- to a real Kubernetes cluster via plain
Deployment/Service/ConfigMap manifests, no Helm or Kustomize.

Why only this subset (not the routers/relay too): see
[`../docs/kubernetes.md`](../docs/kubernetes.md).

## Run it

```sh
brew install kind          # or your platform's equivalent
kind create cluster --name network-lab
kubectl apply -f k8s/
kubectl -n network-lab get pods -w   # wait for all three to be Running
```

Reach the services:

```sh
kubectl -n network-lab port-forward svc/prometheus 9090:9090
kubectl -n network-lab port-forward svc/grafana 3000:3000
```

Prometheus's own targets page (`http://localhost:9090/targets`) should show
`prometheus`, `grafana` and `snmp-exporter` all `UP` -- the same three
services `docker compose up -d` starts under `monitoring/`, running under a
different orchestrator with an adapted scrape config (see
`prometheus-configmap.yaml` for why it isn't a verbatim copy of
`monitoring/prometheus.yml`).

## Tear down

```sh
kind delete cluster --name network-lab
```
