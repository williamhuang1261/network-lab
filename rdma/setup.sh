#!/usr/bin/env bash
# Sets up two Linux network namespaces joined by a veth pair, each with a
# software RoCE (rxe) RDMA device bound to its veth end.
#
# Must run on a real Linux kernel with kernel-module support and root
# privileges -- Docker Desktop's LinuxKit VM has neither (see
# ../docs/rdma.md). Tested inside a Lima Ubuntu VM: `limactl shell default
# -- bash rdma/setup.sh`.
#
# Idempotent: safe to re-run if a previous run partially completed.
set -euo pipefail

NS_A=rdma-a
NS_B=rdma-b
VETH_A=veth-a
VETH_B=veth-b
IP_A=192.168.100.1/24
IP_B=192.168.100.2/24

sudo modprobe rdma_rxe

sudo ip netns add "$NS_A" 2>/dev/null || true
sudo ip netns add "$NS_B" 2>/dev/null || true

if ! sudo ip netns exec "$NS_A" ip link show "$VETH_A" >/dev/null 2>&1; then
    sudo ip link add "$VETH_A" type veth peer name "$VETH_B"
    sudo ip link set "$VETH_A" netns "$NS_A"
    sudo ip link set "$VETH_B" netns "$NS_B"
fi

sudo ip netns exec "$NS_A" ip addr add "$IP_A" dev "$VETH_A" 2>/dev/null || true
sudo ip netns exec "$NS_B" ip addr add "$IP_B" dev "$VETH_B" 2>/dev/null || true

sudo ip netns exec "$NS_A" ip link set "$VETH_A" up
sudo ip netns exec "$NS_A" ip link set lo up
sudo ip netns exec "$NS_B" ip link set "$VETH_B" up
sudo ip netns exec "$NS_B" ip link set lo up

# RDMA devices are visible across all network namespaces once created (the
# kernel's RDMA subsystem is not netns-isolated by default); what actually
# scopes a soft-RoCE device to one side of the link is which netns owns the
# veth netdev it's bound to.
sudo ip netns exec "$NS_A" rdma link add rxe0 type rxe netdev "$VETH_A" 2>/dev/null || true
sudo ip netns exec "$NS_B" rdma link add rxe1 type rxe netdev "$VETH_B" 2>/dev/null || true

echo "== $NS_A: rxe0 on $VETH_A =="
sudo ip netns exec "$NS_A" ibv_devinfo -d rxe0

echo "== $NS_B: rxe1 on $VETH_B =="
sudo ip netns exec "$NS_B" ibv_devinfo -d rxe1
