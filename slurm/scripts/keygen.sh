#!/bin/sh
# One-shot job: generates a fresh munge key into the shared volume if one
# does not already exist there. Never committed to git -- see docs/slurm.md
# and the repo's no-secrets-in-repo rule. Regenerate this for any real
# deployment; this is a throwaway demo key shared over an internal-only
# compose/k8s network.
set -eu

KEY_PATH="/munge-shared/munge.key"

if [ -f "$KEY_PATH" ]; then
    echo "munge key already present at $KEY_PATH, skipping generation"
    exit 0
fi

apt-get update -qq >/dev/null
apt-get install -y --no-install-recommends munge >/dev/null

/usr/sbin/mungekey -f -c -k /etc/munge/munge.key
cp /etc/munge/munge.key "$KEY_PATH"
chmod 400 "$KEY_PATH"
echo "generated new munge key at $KEY_PATH"
