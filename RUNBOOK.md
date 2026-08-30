# Operational run-book

Failure scenarios for this lab, how to recognize them, and how to recover.
Every command below is real and was run against the live stack while writing
this document.

## Before anything: convergence takes real time

Bringing the stack up and testing immediately looks like a failure even when
nothing is wrong:

- OSPF hello/dead timers mean a fresh adjacency needs up to ~40 seconds to
  reach `Full` (`show ip ospf neighbor`) as the DR/BDR election completes.
- Open vSwitch's spanning-tree forward delay holds every port in `learning`
  state for two 15-second intervals (~30-35s total) before it reaches
  `forwarding` (`ovs-appctl stp/show br0`). Pings sent before that fail even
  on a completely correct configuration.

If something looks broken less than a minute after `docker compose up -d`,
wait and recheck before troubleshooting.

## Scenario 1: a link goes down between r1 and r2

**Symptom:** r1 loses reachability to r2's loopback (`10.0.0.2/32`); OSPF
must reconverge.

**Simulate it:**

```
docker compose stop r2
```

**Diagnose:**

```
docker compose exec r1 vtysh -c "show ip ospf neighbor"
```

Once the OSPF dead interval (default 40s) elapses without a hello from r2,
the neighbor entry disappears and the route to `10.0.0.2/32` is withdrawn:

```
docker compose exec r1 vtysh -c "show ip route ospf"
```

no longer lists `10.0.0.2/32`.

**Recover:**

```
docker compose start r2
```

Within one hello interval (default 10s) the adjacency re-forms; within
another ~30s (2x transmit delay plus SPF recalculation) it reaches `Full`
again. Recheck with the same `show ip ospf neighbor` command.

## Scenario 2: the BGP session between r2 and r3 flaps

**Symptom:** r3 loses its route to r1's loopback (learned only via BGP
redistribution, since r3 has no OSPF adjacency of its own).

**Simulate it:**

```
docker compose exec r2 vtysh -c "configure terminal" \
  -c "router bgp 65002" -c "neighbor 10.0.23.3 shutdown"
```

**Diagnose:**

```
docker compose exec r3 vtysh -c "show ip bgp summary"
```

shows the peer state drop out of `Established`; watch `docker compose logs
r3` for the FRR log line marking the peer down. The redistributed route
disappears from:

```
docker compose exec r3 vtysh -c "show ip route bgp"
```

**Recover:**

```
docker compose exec r2 vtysh -c "configure terminal" \
  -c "router bgp 65002" -c "no neighbor 10.0.23.3 shutdown"
```

The session re-establishes within seconds (no BGP hold-timer wait needed on
an administrative shutdown/no-shutdown, unlike a real link flap).

## Scenario 3: a VLAN trunk misconfiguration

**Symptom:** a host that should reach another host in the same VLAN across
the trunk suddenly cannot, or a host that should be isolated suddenly is not.

**Simulate it** (change `h2`'s access-port VLAN tag from 10 to 20, moving it
into `h3`'s VLAN by mistake):

```
docker compose exec ovs ovs-vsctl set port veth-h2 tag=20
```

**Diagnose:**

```
docker compose exec ovs ovs-vsctl show
```

shows `veth-h2` now tagged `20` instead of `10`. The reachability test in
[`docs/vlan-test.md`](docs/vlan-test.md) flips: `h1 -> h2` (both meant to be
VLAN 10) now fails, since `h2` is no longer on VLAN 10:

```
docker compose exec ovs ip netns exec h1 ping -c 2 -W 2 192.168.10.2
```

**Recover:**

```
docker compose exec ovs ovs-vsctl set port veth-h2 tag=10
```

No STP forward-delay wait is needed for this fix — VLAN tag changes on an
already-forwarding port take effect immediately, unlike bringing up a new
port from scratch.

## Scenario 4: the data-relay sender loses its path to the receiver

**Symptom:** `sender` can no longer reach `receiver` (10.0.3.3) because `r2`
is the only path between them and it goes down.

**Simulate it:**

```
docker compose stop r2
docker compose restart sender
```

Restarting `sender` forces a fresh connection attempt during the outage.

**Important caveat, found while testing this exact scenario:** if `sender`
already has an open connection to `receiver` when `r2` goes down, that
existing connection can keep delivering frames for 45+ seconds past the
outage, even though a brand-new connection attempt (or a plain `ping`) fails
immediately. This is a stale per-flow forwarding/route-cache entry in the
Docker Desktop VM's shared host kernel, not a bug in the relay or the
routing config -- see the README's "Engineering notes." **Restarting the
sender**, as above, is what reliably reproduces and demonstrates the
failure/recovery cycle in this environment.

**Diagnose:**

```
docker compose logs sender --tail 10
```

shows repeated `connect attempt N failed (timed out); retrying in Xs` lines
with doubling backoff (0.5s, 1.0s, 2.0s, ... capped at 10s).

**Recover:**

```
docker compose start r2
```

Once OSPF/BGP reconverge (~45s, per the note at the top of this document),
`sender`'s next retry succeeds:

```
docker compose logs sender --tail 5
```

shows `connected to 10.0.3.3:9500 (attempt N)` followed by frame counts
climbing again, and `docker compose logs receiver --tail 5` confirms frames
are actually arriving, not just that the sender believes it reconnected.

## General diagnostics

- `docker compose ps` — confirm every service is `Up`, not restarting.
- `docker compose logs <service>` — FRR logs to stdout (`log stdout` in
  every `frr.conf`); OVS logs to stdout via the entrypoint script.
- `docker compose exec <router> vtysh -c "show running-config"` — confirm
  the config actually running matches the mounted `frr.conf` (a stale mount
  or a manual `vtysh` change that was never saved would otherwise be
  invisible).
- Prometheus target health: `curl -s http://localhost:9090/api/v1/targets`
  — if `frr` targets are down, check the shared `/var/run/frr` Docker volume
  is still mounted in both the router and its `frr-exporter-*` sidecar; if
  `snmp` targets are down, check `docker compose logs r1` (or r2/r3) for
  `snmpd` startup errors; if `relay` targets are down, check
  `docker compose logs sender` / `receiver` for a metrics-server startup
  error (unlikely, since it starts before the socket loop).
