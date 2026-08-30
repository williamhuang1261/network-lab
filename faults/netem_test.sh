#!/bin/bash
# Fault injection against the live r1<->r2 OSPF link using tc netem, run
# from the host against the already-running docker compose stack.
#
# Reports what actually happens under each condition, not a target number:
# - latency and packet loss below OSPF's dead-timer tolerance do NOT cause
#   reconvergence (that is the correct, designed behavior of the dead timer,
#   not a test failure) - this script measures the real effect instead
#   (RTT, loss rate) for those conditions.
# - a full link failure (100% loss) DOES cause reconvergence, and that is
#   the condition this script reports an actual measured time for.
set -euo pipefail
cd "$(dirname "$0")/.."

R1_IFACE=$(docker compose exec -T r1 sh -c \
    "ip -4 -o addr show | grep 10.0.12\\. | awk '{print \$2}'" | tr -d '\r')

if [ -z "$R1_IFACE" ]; then
    echo "Could not determine r1's interface toward r2 (expected an IP in 10.0.12.0/29)." >&2
    exit 1
fi
echo "r1's interface toward r2: $R1_IFACE"

require_full_adjacency() {
    for _ in $(seq 1 20); do
        if docker compose exec -T r1 vtysh -c "show ip ospf neighbor" 2>/dev/null \
            | grep -q "Full"; then
            return 0
        fi
        sleep 3
    done
    echo "OSPF adjacency never reached Full; aborting." >&2
    exit 1
}

echo "=== waiting for baseline Full adjacency ==="
require_full_adjacency
docker compose exec -T r1 vtysh -c "show ip ospf neighbor"

echo
echo "=== condition 1: 100ms latency injected on r1's link to r2 ==="
docker compose exec -T r1 tc qdisc add dev "$R1_IFACE" root netem delay 100ms
sleep 2
echo "--- ping RTT under 100ms injected latency (expect ~100ms+, symmetric so ~200ms round trip) ---"
docker compose exec -T r1 ping -c 5 -W 2 10.0.12.3 | tail -4
echo "--- OSPF adjacency after the injection (expect: still Full, dead timer is 40s, unaffected by 100ms delay) ---"
docker compose exec -T r1 vtysh -c "show ip ospf neighbor" | grep -E "Full|Down" || echo "(no neighbor entry)"
docker compose exec -T r1 tc qdisc del dev "$R1_IFACE" root

echo
echo "=== condition 2: 20% packet loss injected on r1's link to r2 ==="
docker compose exec -T r1 tc qdisc add dev "$R1_IFACE" root netem loss 20%
sleep 2
echo "--- ping loss rate under injected 20% loss ---"
docker compose exec -T r1 ping -c 20 -W 1 -i 0.2 10.0.12.3 | tail -4
echo "--- OSPF adjacency after the injection (expect: still Full most of the time - hellos are sent every 10s and the dead timer tolerates several consecutive misses) ---"
docker compose exec -T r1 vtysh -c "show ip ospf neighbor" | grep -E "Full|Down" || echo "(no neighbor entry)"
docker compose exec -T r1 tc qdisc del dev "$R1_IFACE" root

echo
echo "=== condition 3: full link failure (100% loss) and measured reconvergence ==="
# A single exec session polls from *inside* r1 and only prints on a state
# change, timestamped with the container's own clock. Polling via repeated
# `docker compose exec` calls from the host was tried first and measured
# 570s for a change that should take ~40s - the per-call exec overhead
# under host load was the actual thing being measured, not OSPF. This
# single-session approach removes that confound.
docker compose exec -T r1 tc qdisc add dev "$R1_IFACE" root netem loss 100%
FAIL_START_EPOCH=$(docker compose exec -T r1 date +%s | tr -d '\r')
echo "link failed at t=0 (container clock epoch $FAIL_START_EPOCH)"

DROP_ELAPSED=$(docker compose exec -T r1 sh -c '
    start=$(date +%s)
    while vtysh -c "show ip ospf neighbor" | grep -q Full; do
        sleep 1
    done
    echo $(($(date +%s) - start))
' | tr -d '\r')
echo "neighbor dropped ${DROP_ELAPSED}s after the link failed (dead timer default is 40s)"

echo "restoring the link..."
docker compose exec -T r1 tc qdisc del dev "$R1_IFACE" root

RECOVER_ELAPSED=$(docker compose exec -T r1 sh -c '
    start=$(date +%s)
    while ! vtysh -c "show ip ospf neighbor" | grep -q Full; do
        sleep 1
    done
    echo $(($(date +%s) - start))
' | tr -d '\r')
echo "neighbor reached Full ${RECOVER_ELAPSED}s after the link was restored"
echo
echo "=== summary ==="
echo "down-detection time:  ${DROP_ELAPSED}s"
echo "reconvergence time:   ${RECOVER_ELAPSED}s"
