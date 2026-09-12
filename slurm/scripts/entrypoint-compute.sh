#!/bin/bash
# Starts munged then slurmd in the foreground. This node advertises a
# simulated GPU count via gres.conf -- see docs/slurm.md.
set -eu

MUNGE_SHARED_KEY="/munge-shared/munge.key"

echo "waiting for shared munge key at $MUNGE_SHARED_KEY ..."
until [ -f "$MUNGE_SHARED_KEY" ]; do
    sleep 1
done

install -o munge -g munge -m 400 "$MUNGE_SHARED_KEY" /etc/munge/munge.key
mkdir -p /run/munge && chown munge:munge /run/munge
su -s /bin/sh munge -c /usr/sbin/munged
echo "munged started"

echo "waiting for slurmctld at slurmctld:6817 ..."
until (echo > /dev/tcp/slurmctld/6817) >/dev/null 2>&1; do
    sleep 2
done
echo "slurmctld is reachable"

# Fake GPU device nodes -- copies of /dev/null, created only because
# Slurm's gres/gpu plugin drops any GRES entry with no File= path. No GPU
# driver backs these; see gres.conf and docs/slurm.md.
cp -a /dev/null /dev/fakegpu0
cp -a /dev/null /dev/fakegpu1

exec /usr/sbin/slurmd -D -N slurmd-compute
