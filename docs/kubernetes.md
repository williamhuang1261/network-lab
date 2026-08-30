# Why only the monitoring stack runs on Kubernetes

`k8s/` deploys Prometheus, Grafana and snmp-exporter to a real cluster. The
routers (`r1`/`r2`/`r3`), Open vSwitch (`ovs`), the TCP relay
(`sender`/`receiver`) and the packet decoder stay on Docker Compose. This is
a scope decision made before writing any manifest, not an oversight found
afterward.

## The blocker: one interface per pod

A vanilla Kubernetes pod gets exactly one network interface, on whatever flat
network the cluster's CNI plugin provides. `docker-compose.yml` gives several
services more than one, on separate, statically-addressed bridge networks:

- `r1` sits on three networks at once: `net-r1-r2` (10.0.12.2),
  `net-client` (10.0.1.2) and `net-mgmt` (10.99.0.11).
- `r2` sits on `net-r1-r2` (10.0.12.3), `net-r2-r3` (10.0.23.2) and
  `net-mgmt` (10.99.0.12).
- `r3` sits on `net-r2-r3` (10.0.23.3), `net-server` (10.0.3.2) and
  `net-mgmt` (10.99.0.13).
- `sender` sits on `net-client` and `net-mgmt`; `receiver` sits on
  `net-server` and `net-mgmt`.

This is the whole point of the routing lab: FRR's `ospfd`/`bgpd` need real,
separate point-to-point links to form adjacencies and redistribute routes
across them, and the relay needs a route that actually crosses that routed
path. Collapsing all of that onto one flat pod network would not "port" the
topology, it would replace it with something that no longer runs OSPF/BGP
the way the Docker Compose version demonstrably does.

Reproducing multiple network interfaces per pod in Kubernetes needs a
multi-homing CNI meta-plugin -- **Multus** is the standard one -- attaching
additional `NetworkAttachmentDefinition` interfaces on top of the cluster's
primary CNI. Neither `kind` nor Docker Desktop Kubernetes ship Multus by
default; standing it up is itself a multi-step cluster-admin task (installing
the Multus daemonset, defining a `NetworkAttachmentDefinition` CRD per
bridge, then re-deriving the same static-IPAM scheme `docker-compose.yml`
already encodes). That is real scope, and it buys this CV nothing that
"actual, verified OSPF/BGP/VLAN behavior, on Docker Compose" doesn't already
demonstrate -- the gap this extension is closing is Kubernetes competency
(Deployments, Services, ConfigMaps, verifying real workloads on a real
cluster), not "port an entire routed network onto Kubernetes."

The `ovs` container has the same problem from a different angle: it needs
`privileged: true` for kernel/OVS datapath access and multiple bridges of its
own, neither of which map cleanly onto a Kubernetes pod either. The decoder
container adds a third: `network_mode: "service:r2"`, sharing r2's network
namespace outright so it can see BGP's unicast traffic on r2's own
interfaces -- see the `docker-compose.yml` comment and the README's own
"Independent verification methodology" section for why that specific
placement was necessary. There is no direct Kubernetes equivalent to
`network_mode: service:X`; the nearest analogue is a second container in the
*same pod* as r2, which only works if r2 itself is already a pod, which
circles back to the multi-homing problem above.

## What genuinely has no blocker

Prometheus, Grafana and snmp-exporter, as defined in `docker-compose.yml`,
each sit on exactly one network (`net-mgmt`). Nothing about them needs more
than one interface. That is why this extension deploys those three and
nothing else: it is the subset where "translate the Compose service to a
Kubernetes Deployment/Service/ConfigMap" is actually a faithful translation,
not a silent downgrade dressed up as one.

## What would change this

If a future extension stands up Multus (or swaps the point-to-point bridge
design for something Kubernetes-native, e.g. a CNI that supports multiple
pod networks out of the box), the routing layer becomes portable and this
document's scope note should be revisited rather than left stale.
