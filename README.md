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
- **Fault injection and an independent packet decoder** (`faults/`,
  `decoder/`): `tc netem` induces real link latency, loss and failure, with
  measured (not assumed) OSPF reconvergence time; a from-the-wire Scapy
  decoder infers OSPF/BGP state with no access to FRR's own config or
  control sockets, cross-checked against `vtysh`'s own reported state.
- An **RDMA lab** (`rdma/`): a software RoCE (`rxe`) device pair bound
  across two Linux network namespaces, plus real measured RDMA write/read
  bandwidth and latency benchmarks (`ib_write_bw`/`ib_read_bw`/
  `ib_write_lat`) over `rdma-core`'s `perftest` tools. Runs inside a Lima
  VM, not Docker Compose -- see [`docs/rdma.md`](docs/rdma.md) for why.
- **Terraform + ArgoCD** (`terraform/`): Terraform provisions the
  `network-lab`/`argocd` namespaces and installs ArgoCD on the same `kind`
  cluster `k8s/`'s manifests already run on, then registers those manifests
  as an ArgoCD `Application`. From there ArgoCD, not `kubectl apply`, keeps
  the live monitoring stack in sync with this repo -- see
  [`docs/gitops.md`](docs/gitops.md) for the ownership split and a real
  edit-commit-push-sync round trip.

- **Slurm** (`slurm/`, `k8s-slurm/`): a real `slurmctld`/`slurmdbd`/`slurmd`
  cluster (not a mock scheduler) with one compute node advertising a
  simulated GPU resource, runnable both as a standalone Docker Compose stack
  and on the same `kind` cluster the monitoring stack runs on, registered as
  a second ArgoCD `Application` (`terraform/application-slurm.tf`). GRES-aware
  queueing (`squeue`) and accounting (`sacct`) are verified against real
  multi-job submissions -- see [`docs/slurm.md`](docs/slurm.md) for the
  simulated-GPU disclosure.

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

**Also available on Kubernetes:** the monitoring stack (Prometheus, Grafana,
snmp-exporter) has its own Deployment/Service/ConfigMap manifests in `k8s/`.
Two ways to run them on a real local cluster:

- Manual: `kind create cluster` + `kubectl apply -f k8s/` -- see
  `k8s/README.md`.
- Terraform + ArgoCD (the way the cluster is actually operated now):
  ```
  kind create cluster --name network-lab
  cd terraform && terraform init && terraform apply
  ```
  Terraform provisions the namespaces and ArgoCD itself, then registers
  `k8s/` as an ArgoCD `Application` with automated sync -- ArgoCD applies
  and reconciles the manifests from there, not `terraform apply` or manual
  `kubectl apply`. See [`docs/gitops.md`](docs/gitops.md) for the full
  ownership split, the CRD-ordering constraint that forces a two-pass
  apply, and a real edit-commit-push-sync round trip.

See `docs/kubernetes.md` for why the routing/relay layer stays on Docker
Compose rather than being ported too.

**Running the decoder's test suite** (no Docker Compose stack needed):

```
pip install -r decoder/requirements-dev.txt
pytest decoder/tests/
```

18 tests over `decoder/ospf_bgp_decoder.py`'s OSPF/BGP state-inference rules
(synthetic Scapy packets, no live capture) and `decoder/cross_check.py`'s
text-parsing functions (real decoder-log lines plus representative FRR
`vtysh` output). `decoder/cross_check.py`'s end-to-end `main()` still needs
a running topology and is exercised by actually running it, not by this
suite -- see `docs/decoder_verification.md`.

**Running the RDMA lab** (needs a real Linux kernel with kernel-module
support -- not Docker Desktop, see `docs/rdma.md`):

```
limactl shell default -- bash rdma/setup.sh    # rxe0/rxe1 device pair
limactl shell default -- bash rdma/bench.sh    # write/read bandwidth + latency
```

Real measured numbers are in `docs/rdma-results.md`.

**Running the Slurm simulated-GPU demo** -- standalone, no Kubernetes needed:

```
docker compose -f slurm/docker-compose.slurm.yml up --build -d
# wait for the compute node to report idle (see docs/slurm.md re: startup time)
docker exec slurm-slurmctld-1 sinfo
docker cp slurm/jobs/gpu_job.sh slurm-slurmctld-1:/tmp/gpu_job.sh
docker exec -u slurm slurm-slurmctld-1 bash -c \
  "chown slurm:slurm /tmp/gpu_job.sh; sbatch /tmp/gpu_job.sh; sbatch /tmp/gpu_job.sh; sbatch /tmp/gpu_job.sh"
docker exec -u slurm slurm-slurmctld-1 squeue
```

Or on the same `kind` cluster the monitoring stack uses, GitOps-managed via
the `network-lab-slurm` ArgoCD Application:

```
bash scripts/deploy-k8s-slurm.sh
```

Generates a fresh munge key and loads it as a Kubernetes Secret (never
committed -- see `docs/slurm.md`), builds and loads the controller/compute
images into `kind`, and applies `k8s-slurm/`.

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

**Measured OSPF reconvergence under a real link failure** (three trials,
full detail in [`docs/reconvergence.md`](docs/reconvergence.md)):

```
$ bash faults/netem_test.sh
link failed at t=0 (container clock epoch ...)
neighbor dropped 42s after the link failed (dead timer default is 40s)
restoring the link...
neighbor reached Full 10s after the link was restored
```

**An independent packet decoder inferring OSPF/BGP state from raw wire
captures alone, agreeing with FRR's own state** (full detail in
[`docs/decoder_verification.md`](docs/decoder_verification.md)):

```
$ python3 decoder/cross_check.py
[decoder] OSPF 10.0.0.1 <-> 10.0.0.2: inferred FULL (2-Way via mutual Hello + LS-Update observed from [...])
[decoder] BGP 10.0.23.2 <-> 10.0.23.3: inferred ESTABLISHED (OPEN + KEEPALIVE observed from both sides)
OSPF: decoder says Full=True, FRR says Full=True -> AGREE
BGP: decoder says Established=True, FRR says Established=True -> AGREE
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

**Slurm GRES-aware queueing** (three jobs against two simulated GPUs; full
detail and the simulated-GPU disclosure in [`docs/slurm.md`](docs/slurm.md)):

```
$ squeue
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
                 3       gpu gpu-demo    slurm PD       0:00      1 (Resources)
                 1       gpu gpu-demo    slurm  R       0:02      1 slurmd-compute
                 2       gpu gpu-demo    slurm  R       0:02      1 slurmd-compute

$ sacct -j 1,2,3 --format=JobID,JobName,Partition,AllocTRES%40,State,ExitCode,Elapsed
JobID           JobName  Partition                                AllocTRES      State ExitCode    Elapsed
------------ ---------- ---------- ---------------------------------------- ---------- -------- ----------
1              gpu-demo        gpu        billing=1,cpu=1,gres/gpu=1,node=1  COMPLETED      0:0   00:00:20
2              gpu-demo        gpu        billing=1,cpu=1,gres/gpu=1,node=1  COMPLETED      0:0   00:00:20
3              gpu-demo        gpu        billing=1,cpu=1,gres/gpu=1,node=1  COMPLETED      0:0   00:00:20
```

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
- **`tc netem`** for fault injection — already present in the router images
  via `iproute2`, no extra tooling needed.
- **Scapy** for the independent packet decoder — genuinely parses OSPF/BGP
  wire format itself, not a wrapper around FRR's own state.
- **Slurm (`slurm-wlm` 21.08)** — a real workload manager, not a scheduler
  simulator; GRES-aware queueing and slurmdbd-backed accounting are exercised
  against genuine `sbatch`/`squeue`/`sacct` calls.

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

**A Linux bridge does not flood unicast traffic to a merely-promiscuous
port.** The independent packet decoder was first built as a fourth container
sitting on the same bridge networks as the routers, in promiscuous mode. It
saw OSPF fine (multicast Hello/LS-Update traffic gets flooded to every port
on a bridge without IGMP snooping) but never saw a single BGP packet, even
with `tcpdump` directly on the interface. A Docker bridge is a real Linux
bridge: for known unicast MAC addresses it switches traffic directly between
the two ports involved, exactly like a physical switch, and promiscuous mode
on a third port only affects what that port's NIC will accept, not what the
switch chooses to forward there. The fix was to run the decoder inside `r2`'s
own network namespace (`network_mode: service:r2`) instead of as a bystander
on the bridge -- the same way a real engineer would `tcpdump` the router
itself rather than hope for port mirroring that was never configured.

**The first fault-injection reconvergence measurement was wrong, and the
wrongness was itself informative.** Polling OSPF neighbor state via repeated
separate `docker compose exec` calls from the host measured 570s for a
link-failure detection that should take about 40s (the OSPF dead timer).
That number was the overhead of spawning a new `docker exec` session on
every poll under host load, not OSPF's actual behavior. Switching to a
single exec session that polls internally and timestamps with the
container's own clock brought the measurement in line with the dead timer
(35-42s across two of three runs). See `docs/reconvergence.md` for the full
methodology note and why the third run's 124s outlier was kept rather than
discarded.

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
- The independent decoder's OSPF "Full" criterion (2-Way plus an LS-Update
  from either side) is deliberately weaker than RFC 2328's exact state
  machine, and the decoder's own docstring says so — it does not track LSA
  sequence numbers or replicate FRR's neighbor FSM bit-for-bit.
- The decoder only observes traffic through r2, since it runs inside r2's
  own network namespace; it has no visibility into anything on r1's or r3's
  other interfaces that doesn't cross r2.
- The routers, Open vSwitch and the relay run on Docker Compose only, not
  Kubernetes — their multi-interface, statically-addressed bridge topology
  needs Multus CNI, not present in `kind`/Docker Desktop Kubernetes by
  default; see `docs/kubernetes.md` for the specifics. Only the
  single-network monitoring stack (`k8s/`) runs on both.
- The RDMA lab runs inside a Lima VM, not Docker Compose — Docker Desktop's
  LinuxKit VM has no loadable kernel-module support. The measured
  bandwidth/latency numbers come from a single `rxe` device looped back to
  itself, not from `setup.sh`'s two-namespace `rxe0`/`rxe1` pair — RDMA
  data-plane traffic doesn't survive that veth/netns boundary in this VM's
  kernel, even though plain ICMP does; see `docs/rdma.md` for the full
  investigation.
- No physical or real GPU anywhere in the Slurm extension — the compute
  node's `gpu:2` GRES is backed by two `/dev/null` stand-ins, not an actual
  accelerator, no CUDA runtime or NVIDIA driver is installed, and
  `CUDA_VISIBLE_DEVICES` is only the GRES index Slurm handed the job, never
  a real device; see `docs/slurm.md` for the full disclosure and a real
  slurmctld/slurmd startup-latency finding in this VM.
