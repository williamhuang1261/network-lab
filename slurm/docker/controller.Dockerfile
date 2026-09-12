# Slurm controller image: slurmctld + slurmdbd + munge, no compute daemon.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        slurmctld \
        slurmdbd \
        munge \
        mariadb-client \
        gosu \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/spool/slurmctld /var/run/slurm /var/log/slurm \
    && chown slurm:slurm /var/spool/slurmctld /var/run/slurm /var/log/slurm

COPY config/slurm.conf /etc/slurm/slurm.conf
COPY config/gres.conf /etc/slurm/gres.conf
COPY scripts/slurmdbd.conf /etc/slurm/slurmdbd.conf
COPY scripts/entrypoint-controller.sh /usr/local/bin/entrypoint-controller.sh
RUN chmod 600 /etc/slurm/slurmdbd.conf \
    && chown slurm:slurm /etc/slurm/slurmdbd.conf \
    && chmod +x /usr/local/bin/entrypoint-controller.sh

ENTRYPOINT ["/usr/local/bin/entrypoint-controller.sh"]
