# Kubernetes manifests -- Slurm simulated-GPU demo

Deploys the same `slurmctld`/`slurmdbd`/`slurmd`/munge stack as
`../slurm/docker-compose.slurm.yml`, as Deployments on the `network-lab`
kind cluster's existing namespace, GitOps-managed by the
`network-lab-slurm` ArgoCD Application (`../terraform/application-slurm.tf`).

The `slurm-munge-key` Secret referenced here is **not** in this directory --
it is generated fresh and applied out-of-band by
`../scripts/deploy-k8s-slurm.sh`, never committed to git. See
`../docs/slurm.md` for why, plus the simulated-GPU disclosure and a real
slurmctld/slurmd startup-latency finding.

## Run it

```sh
kind create cluster --name network-lab   # if not already running
bash ../scripts/deploy-k8s-slurm.sh
kubectl -n network-lab get pods -l 'app in (mariadb,slurmctld,slurmd-compute)' -w
```

Wait for `sinfo` (exec'd into the `slurmctld` pod) to report the compute
node `idle`, not `unk*`, before submitting jobs -- see `../docs/slurm.md`.
