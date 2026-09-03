#!/usr/bin/env bash
# Runs real RDMA write/read bandwidth and write-latency benchmarks over a
# soft-RoCE (rxe) device, using rdma-core's perftest tools
# (ib_write_bw/ib_read_bw/ib_write_lat).
#
# Topology: a single rxe device bound to the VM's own NIC (self-loopback:
# client and server both connect to the device's own IP). This is NOT the
# rxe0/rxe1 pair setup.sh creates across two network namespaces -- see
# ../docs/rdma.md for exactly why: that veth-crossed topology creates real,
# PORT_ACTIVE RDMA devices, but data-plane traffic (perftest's RC writes)
# does not survive the veth/netns boundary in this VM's kernel, even though
# plain ICMP does. Self-loopback on the VM's real NIC is the topology that
# actually carries RDMA traffic here, so that's what this script measures.
#
# Must run on a real Linux kernel with kernel-module support (see
# ../docs/rdma.md) -- tested inside a Lima Ubuntu VM:
# `limactl shell default -- bash rdma/bench.sh`.
set -euo pipefail

DEV=rxe-eth0
NETDEV=eth0
IP=$(ip -4 -o addr show "$NETDEV" | awk '{print $4}' | cut -d/ -f1)

sudo modprobe rdma_rxe
if ! sudo rdma link show "$DEV" >/dev/null 2>&1; then
    sudo rdma link add "$DEV" type rxe netdev "$NETDEV"
fi

cleanup() {
    sudo rdma link delete "$DEV" 2>/dev/null || true
}
trap cleanup EXIT

run_bw() {
    local tool=$1 label=$2
    "$tool" -d "$DEV" -x 1 --report_gbits > /tmp/rdma-bench-server.log 2>&1 &
    local server_pid=$!
    sleep 1
    "$tool" -d "$DEV" -x 1 --report_gbits "$IP" > /tmp/rdma-bench-client.log 2>&1
    wait "$server_pid"
    echo "-- $label --"
    grep -A1 "MsgRate" /tmp/rdma-bench-client.log
}

run_lat() {
    ib_write_lat -d "$DEV" -x 1 > /tmp/rdma-bench-server.log 2>&1 &
    local server_pid=$!
    sleep 1
    ib_write_lat -d "$DEV" -x 1 "$IP" > /tmp/rdma-bench-client.log 2>&1
    wait "$server_pid"
    echo "-- RDMA write latency --"
    grep -A1 "t_avg" /tmp/rdma-bench-client.log
}

echo "device: $DEV on $NETDEV ($IP)"
echo

for i in 1 2 3; do
    echo "=== write bandwidth, trial $i ==="
    run_bw ib_write_bw "RDMA write bandwidth"
done

for i in 1 2 3; do
    echo "=== read bandwidth, trial $i ==="
    run_bw ib_read_bw "RDMA read bandwidth"
done

for i in 1 2 3; do
    echo "=== write latency, trial $i ==="
    run_lat
done
