# Slurm compute node image: slurmd + munge only. Declares a simulated GPU
# resource via gres.conf -- no physical GPU driver or nvidia-smi is present
# in this image (see docs/slurm.md).
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        slurmd \
        slurm-client \
        munge \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/spool/slurmd /var/run/slurm /var/log/slurm

COPY config/slurm.conf /etc/slurm/slurm.conf
COPY config/gres.conf /etc/slurm/gres.conf
COPY scripts/entrypoint-compute.sh /usr/local/bin/entrypoint-compute.sh
RUN chmod +x /usr/local/bin/entrypoint-compute.sh

ENTRYPOINT ["/usr/local/bin/entrypoint-compute.sh"]
