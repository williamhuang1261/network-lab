#!/bin/bash
#SBATCH --job-name=gpu-demo
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --ntasks=1
#SBATCH --time=00:02:00
#SBATCH --output=/tmp/slurm-job-%j.out

echo "job $SLURM_JOB_ID starting on $(hostname) with GRES $SLURM_JOB_GPUS"
echo "requested simulated GPU device(s): $CUDA_VISIBLE_DEVICES"
sleep 20
echo "job $SLURM_JOB_ID done"
