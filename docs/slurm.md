# The Slurm extension's simulated GPUs, and the constraints found building it

Stated plainly, the same honesty standard as `docs/rdma.md`'s RDMA loopback
scope note.

## No physical GPU is present anywhere in this extension

`slurm/config/gres.conf` declares the compute node's `gpu` GRES type against
`/dev/fakegpu0` and `/dev/fakegpu1`, which `slurm/scripts/entrypoint-compute.sh`
creates at container start as plain copies of `/dev/null`:

```
cp -a /dev/null /dev/fakegpu0
cp -a /dev/null /dev/fakegpu1
```

This exists only because Slurm's `gres/gpu` plugin silently drops any GRES
entry with no `File=` path (confirmed directly: `slurmd -Dvvv` with
`DebugFlags=Gres` logged `Removing file-less GPU gpu:(null) from final GRES
list` when `gres.conf` declared `Count=2` with no `File=`). Pointing `File=`
at real files was the fix; the files themselves carry no device semantics,
no driver, and are never opened by any job. `CUDA_VISIBLE_DEVICES` is set by
Slurm per job (see `slurm/jobs/gpu_job.sh`) purely as the GRES index Slurm
handed out, not because a CUDA runtime exists in either image, and neither
image installs the NVIDIA driver, `nvidia-smi`, or CUDA toolkit. What is real
is the scheduler behavior: GRES-aware queueing, per-job GRES allocation, and
accounting, all verified against a genuine `slurmctld`/`slurmdbd`/`slurmd`
cluster (see below), not a mock or a stubbed-out API.

## Verified scheduling behavior

Submitting three copies of `slurm/jobs/gpu_job.sh` (`--gres=gpu:1` each)
against the compute node's two declared GPUs, both locally
(`slurm/docker-compose.slurm.yml`) and after porting the same images to the
existing kind cluster (`k8s-slurm/`, `scripts/deploy-k8s-slurm.sh`):

```
$ squeue
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
                 3       gpu gpu-demo    slurm PD       0:00      1 (Resources)
                 1       gpu gpu-demo    slurm  R       0:02      1 slurmd-compute
                 2       gpu gpu-demo    slurm  R       0:02      1 slurmd-compute
```

Job 3 queues on `Resources` (both simulated GPUs already allocated to jobs 1
and 2), then runs once one finishes:

```
$ sacct -j 1,2,3 --format=JobID,JobName,Partition,AllocTRES%40,State,ExitCode,Elapsed
JobID           JobName  Partition                                AllocTRES      State ExitCode    Elapsed
------------ ---------- ---------- ---------------------------------------- ---------- -------- ----------
1              gpu-demo        gpu        billing=1,cpu=1,gres/gpu=1,node=1  COMPLETED      0:0   00:00:20
1.batch           batch                       cpu=1,gres/gpu=1,mem=0,node=1  COMPLETED      0:0   00:00:20
2              gpu-demo        gpu        billing=1,cpu=1,gres/gpu=1,node=1  COMPLETED      0:0   00:00:20
2.batch           batch                       cpu=1,gres/gpu=1,mem=0,node=1  COMPLETED      0:0   00:00:20
3              gpu-demo        gpu        billing=1,cpu=1,gres/gpu=1,node=1  COMPLETED      0:0   00:00:20
3.batch           batch                       cpu=1,gres/gpu=1,mem=0,node=1  COMPLETED      0:0   00:00:20
```

`gres/gpu=1` shows up in real accounting output (`AccountingStorageTRES=gres/gpu`
in `slurm/config/slurm.conf`), backed by a genuine `slurmdbd` + MariaDB
accounting store, not a job-completion log substitute. The two jobs each
received a distinct simulated device index (`CUDA_VISIBLE_DEVICES=0` and
`=1` respectively, printed in the job's own stdout), confirming Slurm's GRES
allocator, not just its counting, is exercised.

## Why the munge key is never committed

`slurm`'s controller and compute nodes must share one munge key to
authenticate RPCs between `slurmctld`, `slurmdbd` and `slurmd`. Locally,
`slurm/scripts/keygen.sh` generates a fresh key into a Docker Compose named
volume the first time the stack starts. In Kubernetes,
`scripts/deploy-k8s-slurm.sh` generates a fresh key the same way and loads it
as a `slurm-munge-key` Secret via `kubectl create secret ... | kubectl apply
-f -`, never writing the key to disk in this repo. Neither `slurm.conf` nor
`gres.conf` contain secrets, so both are safe to manage through the
`network-lab-slurm` ArgoCD Application (`terraform/application-slurm.tf`);
the Secret is deliberately outside GitOps for the same reason
`terraform/application.tf`'s monitoring stack never checked in credentials.

## A real startup-latency finding

Both `slurmctld` and `slurmd` take on the order of one to two minutes to
finish their first startup in this environment (Docker Desktop's ARM64 VM
locally, and the same VM's `kind` node in Kubernetes) before they bind their
RPC ports, visible as a single process pinned near 100% CPU with no forward
progress in the logs during that window. This reproduced identically across
multiple clean restarts in both the Compose and Kubernetes deployments, so
it is a property of this environment rather than a one-off fluke -- most
likely munge's or Slurm's own credential/key setup contending for entropy or
CPU inside a lightly-provisioned VM, though the exact mechanism was not
instrumented further. `scripts/deploy-k8s-slurm.sh`'s printed rollout check
and this repo's README both call out to wait for `sinfo` to report the node
`idle` (not `unk*`) before submitting jobs, rather than assuming a `Running`
pod means the scheduler is ready.

## What would change this

If a future iteration moves this off Docker Desktop's VM (a bare-metal Linux
host, or a cloud-hosted `kind`/EKS node), both the slow-startup finding above
and the two device stand-ins in `gres.conf` are worth re-testing: a real
GPU-equipped node would use `AutoDetect=nvml` and a real NVIDIA device
plugin instead of the file stand-ins this extension uses.
