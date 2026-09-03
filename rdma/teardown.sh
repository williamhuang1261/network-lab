#!/usr/bin/env bash
# Tears down the soft-RoCE lab created by setup.sh. Safe to re-run.
set -uo pipefail

sudo ip netns exec rdma-a rdma link delete rxe0 2>/dev/null
sudo ip netns exec rdma-b rdma link delete rxe1 2>/dev/null
sudo ip netns delete rdma-a 2>/dev/null
sudo ip netns delete rdma-b 2>/dev/null

echo "torn down"
