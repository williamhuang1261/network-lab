# network-lab

A Docker Compose network engineering lab that runs real routing and
switching daemons — not mocks — to demonstrate OSPF, BGP with route
redistribution, VLAN trunking with spanning-tree, and SNMP/protocol-state
monitoring.

## What it is

- **FRRouting** (the open-source router used in real production networks)
  running `ospfd` and `bgpd` across three containers, `r1`/`r2`/`r3`.
- **Open vSwitch**, two bridges linked by an 802.1Q trunk, carrying two
  VLANs between three "host" network namespaces.
- **Prometheus + snmp_exporter + frr_exporter + Grafana**, scraping both
  interface counters (SNMP) and protocol state (OSPF/BGP neighbor status,
  read directly off each router's vtysh sockets).
- A **TCP data-relay** (`relay/`) streaming real payload data end-to-end
  across the routed topology, with reconnect/retry on a real router outage
  and its own metrics on the same Grafana dashboard.

See [`docs/topology.md`](docs/topology.md) for the full diagram.

## Why

Closes a gap between a software/quant-focused CV and postings that ask for
hands-on IP networking: L2/L3 protocols, VLANs, and monitoring of network
services. Every claim here is backed by a command that was actually run
against a live daemon — see the sample output below.

## Running it

Requires Docker (Docker Compose v2). From the repo root:

```
docker compose up -d --build
```

Give it about 40 seconds: OSPF/BGP hello and dead timers, and Open vSwitch's
spanning-tree forward delay, both need real wall-clock time to converge —
see `RUNBOOK.md` for why a routing/switching lab isn't a check right after
`up`.

```
docker compose ps
```

should show `r1`, `r2`, `r3`, `ovs`, `sender`, `receiver`,
`frr-exporter-r1/2/3`, `snmp-exporter`, `prometheus` and `grafana`, all `Up`.

Grafana: http://localhost:3000 (anonymous viewer access enabled for the
demo). Prometheus: http://localhost:9090.

```
docker compose down
```

## Sample output

**OSPF full adjacency (r1 <-> r2):**

```
$ docker compose exec r1 vtysh -c "show ip ospf neighbor"
Neighbor ID     Pri State           Up Time         Dead Time Address         Interface                        RXmtL RqstL DBsmL
10.0.0.2          1 Full/DR         12.452s           37.541s 10.0.12.3       eth1:10.0.12.2                       0     0     0
```

**BGP session and OSPF-to-BGP redistribution (r3 has no OSPF adjacency of
its own, yet learns r1's loopback via BGP):**

```
$ docker compose exec r3 vtysh -c "show ip bgp summary"
Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
10.0.23.2       4      65002         5         7        0    0    0 00:00:52            1        4 N/A

$ docker compose exec r3 vtysh -c "show ip route bgp"
B>* 10.0.0.1/32 [20/10] via 10.0.23.2, eth1, weight 1, 00:00:03
```

**VLAN trunk vs. isolation** (full detail and STP forward-delay note in
[`docs/vlan-test.md`](docs/vlan-test.md)):

```
$ docker compose exec ovs ip netns exec h1 ping -c 2 -W 2 192.168.10.2   # same VLAN, across the trunk
2 packets transmitted, 2 received, 0% packet loss

$ docker compose exec ovs ip netns exec h1 ping -c 2 -W 2 192.168.10.3   # different VLAN, same subnet, same switch
2 packets transmitted, 0 received, 100% packet loss
```

**Spanning-tree enabled and forwarding:**

```
$ docker compose exec ovs ovs-appctl stp/show br0
Interface  Role       State      Cost  Pri.Nbr
trunk-br0  designated forwarding 2     128.1
veth-h3    designated forwarding 2     128.2
veth-h1    designated forwarding 2     128.3
```

**End-to-end data relay across the full routed path** (sender, behind r1, to
receiver, behind r3, three real router hops apart):

```
$ docker compose exec sender ping -c 3 -W 2 10.0.3.3
64 bytes from 10.0.3.3: seq=0 ttl=61 time=0.339 ms   # ttl=61 confirms 3 real hops
3 packets transmitted, 3 packets received, 0% packet loss

$ docker compose logs receiver --tail 3
[receiver] frames=30 bytes=680 last_payload=b'frame-29-...'
```

**Reconnect/retry across a real router outage** (r2 stopped, the sender's
existing frame count and r2's logs shown for context):

```
$ docker compose stop r2 && docker compose restart sender
[sender] connect attempt 1 failed (timed out); retrying in 0.5s
[sender] connect attempt 2 failed (timed out); retrying in 1.0s
...
[sender] connect attempt 6 failed (timed out); retrying in 10.0s
$ docker compose start r2   # ~45s later, once OSPF/BGP reconverge:
[sender] connected to 10.0.3.3:9500 (attempt 7)
[sender] sent 10 frames total (reconnects=0)
```

**Monitoring, all targets healthy:**

```
$ curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health}'
frr frr-exporter-r1:9342 up
frr frr-exporter-r2:9342 up
frr frr-exporter-r3:9342 up
relay sender:9600 up
relay receiver:9600 up
snmp 10.99.0.11:1161 up
snmp 10.99.0.12:1161 up
snmp 10.99.0.13:1161 up
```

The Grafana dashboard (`Network Lab`, auto-provisioned, 8 panels) shows OSPF
neighbor state, BGP peer state, FRR daemon liveness, per-interface throughput
derived from `ifHCInOctets`/`ifHCOutOctets`, a table of `ifOperStatus`, and
the relay's own frame rate and reconnect count.

## Stack

- **FRRouting** — a real router implementation, not a hand-rolled OSPF/BGP
  state machine. The point is running the same daemons that operate real
  networks.
- **Open vSwitch, userspace/netdev datapath** — no kernel module needed, so
  it runs identically on any Docker host, trading raw throughput (irrelevant
  for a demo lab) for portability.
- **frr_exporter** (maintained by the FRR project) — plain SNMP (MIB-II)
  only exposes interface counters, not OSPF/BGP neighbor state without
  vendor-specific MIBs; frr_exporter reads each daemon's own vtysh unix
  socket for that, over a Docker volume shared with the router container.
- **Docker Compose** — every link is a Docker bridge network; no
  containerlab, no host-level network-namespace manipulation (see
  "Engineering notes" below for why).
- **Python, standard library only** for the TCP relay and its metrics
  server — no dependency to justify beyond what ships with the interpreter.

## Engineering notes

**Why not containerlab?** containerlab wires topologies with veth pairs
directly in the host's root network namespace. On Docker Desktop for Mac,
"the host" from containerlab's point of view is the macOS host, which has no
Linux network namespaces at all — the real Linux environment is hidden
inside Docker Desktop's own VM. containerlab would not run there. Docker
Compose with FRRouting and Open vSwitch containers gets the same protocol
coverage using only Docker's own container networking, which behaves
identically on macOS and Linux — and every step in this repo's build was
verified by actually running it, not just written and assumed correct.

**Why the VLAN isolation test uses the same IP subnet for both VLANs.**
Pinging across different subnets fails with "network unreachable" from
routing, regardless of whether VLANs isolate anything. Putting `h1` (VLAN 10)
and `h3` (VLAN 20) on the same `192.168.10.0/24` subnet makes the failure a
genuine ARP/L2-level isolation result instead.

**Why hosts are network namespaces inside one `ovs` container, not separate
Docker containers.** Wiring a veth pair between two *separate* Docker
containers requires reaching into each container's network namespace from
outside — normally done by bind-mounting Docker's netns directory and using
`ip netns exec` against another container's PID, which is fragile and
under-documented on Docker Desktop for Mac. Standing up the bridges and the
"hosts" as Linux network namespaces inside one privileged container sidesteps
that entirely while testing the identical VLAN/STP behavior.

**A real bug found and fixed along the way (not a hypothetical):** FRR's own
`interface eth0 / ip address ...` configuration stanzas raced Docker's IPAM
assignment on container start, leaving duplicate stale IP addresses on *both*
physical interfaces of a multi-homed router. Fixed by dropping FRR-managed
addressing on physical interfaces entirely — Docker's `ipv4_address` is now
the only source of truth for interface IPs, and FRR only manages the
loopback, which Docker does not touch.

**Another one:** net-snmp's `agentaddress udp:<ip>:<port>` syntax reliably
failed to bind in this container environment with "Error opening specified
endpoint," even against a demonstrably free port (verified with `socat`).
The bare `agentaddress <port>` form (binding all interfaces) works. snmpd's
own daemonizing fork also silently exits 1 here, so it runs in foreground,
backgrounded by the entrypoint script instead of relying on `snmpd`'s
own `-c`-triggered fork.

**A third:** `net.ipv4.ip_forward` was never enabled on `r1`/`r2`/`r3` until
the relay work needed genuine end-to-end packet forwarding. FRR/zebra
programs the kernel's routing table, but does not itself flip the kernel's
forwarding sysctl -- every verification before that point checked route
tables and router-to-router reachability, never an actual multi-hop data
path through a middle router. Real end-to-end forwarding was only exercised,
and only worked, once `sysctls: [net.ipv4.ip_forward=1]` was added to all
three router services.

**A genuinely interesting one, left in rather than smoothed over:** stopping
`r2` correctly and immediately breaks *new* connections and pings (a fresh
`ping` or `connect()` attempt fails right away, and `r1`'s own routing table
correctly withdraws the route within one OSPF dead interval). But an
*already-established* sender-to-receiver TCP connection kept delivering
frames for 45+ seconds into the same outage -- almost certainly a stale
per-flow forwarding or route-cache entry in the Docker Desktop VM's shared
host kernel that outlives the FRR-managed routing table update visible
inside the containers. Setting `TCP_USER_TIMEOUT` on the socket (5s) did not
close this gap either. Because of this, the relay's verified reconnect
behavior is scoped to a fresh connection attempt (triggered here by
restarting the sender container, which is what a real crash, deploy, or
watchdog restart would also produce) rather than live mid-stream stall
detection, which this test environment cannot reliably exercise. See
`RUNBOOK.md` for the exact reproduction.

## What is deliberately not here

- No real hardware, no physical switches or routers, no cabling — this is a
  software-only lab; the physical-layer/cabling part of the posting this
  project targets is not addressed here.
- No IS-IS, MPLS, VRRP, LACP, MC-LAG, EVPN/VXLAN, or ACLs — the lab focuses
  on OSPF, BGP redistribution, VLAN trunking and STP, and monitoring, not
  the full breadth of protocols a posting might list.
- No authentication on OSPF/BGP sessions, no SNMPv3 (the lab uses SNMPv2c
  `public` community, explicitly documented as lab-only, never exposed
  outside the Docker-internal `net-mgmt` network).
- The Open vSwitch bridges run in userspace/netdev mode, not the kernel
  datapath — a deliberate portability trade-off, not a claim about
  production-grade throughput.
- No encryption or authentication on the relay's wire protocol -- the point
  of `relay/` is the transport, framing, and reconnect behavior, not a
  secure protocol.
- The relay's reconnect logic is verified against a fresh connection attempt
  during an outage, not against a live connection detecting a mid-stream
  stall in this specific test environment (see "Engineering notes").
