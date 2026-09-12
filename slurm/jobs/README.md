# Slurm demo jobs

`gpu_job.sh` is a plain `sbatch` batch script that requests one simulated
GPU (`--gres=gpu:1`) from the `gpu` partition and sleeps 20 seconds so its
runtime overlaps with other submissions.

Submitting three of these against the compute node's two declared GPUs
demonstrates real GRES-aware scheduling: the third job queues with
`Reason=Resources` until one of the first two finishes and its GPU is
freed. See `docs/slurm.md` for the observed `squeue`/`sacct` output and the
job's simulated-GPU disclosure (`CUDA_VISIBLE_DEVICES` is printed only to
show what Slurm hands the job, not because a CUDA runtime is present).
