#!/bin/bash
# Starts munged, slurmdbd and slurmctld in one container. See docs/slurm.md
# for why controller+dbd are combined here (fewer moving parts than a
# three-way split, still a real slurmctld/slurmdbd/munge stack).
set -eu

MUNGE_SHARED_KEY="/munge-shared/munge.key"

echo "waiting for shared munge key at $MUNGE_SHARED_KEY ..."
until [ -f "$MUNGE_SHARED_KEY" ]; do
    sleep 1
done

install -o munge -g munge -m 400 "$MUNGE_SHARED_KEY" /etc/munge/munge.key
mkdir -p /run/munge && chown munge:munge /run/munge
gosu munge /usr/sbin/munged
echo "munged started"

echo "waiting for mariadb at mariadb:3306 ..."
until mysqladmin ping -h mariadb -u slurm -pslurm-demo-password --silent >/dev/null 2>&1; do
    sleep 2
done
echo "mariadb is reachable"

gosu slurm /usr/sbin/slurmdbd -D &
SLURMDBD_PID=$!

echo "waiting for slurmdbd to accept connections on port 6819 ..."
until (echo > /dev/tcp/127.0.0.1/6819) >/dev/null 2>&1; do
    sleep 1
done
echo "slurmdbd is up (pid $SLURMDBD_PID)"

# Register this cluster with slurmdbd before slurmctld tries to report to
# it -- a fresh accounting DB has no cluster row yet.
gosu slurm sacctmgr -i add cluster network-lab || true

exec gosu slurm /usr/sbin/slurmctld -D
