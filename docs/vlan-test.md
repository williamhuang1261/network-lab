# VLAN trunk / isolation test

Topology (built by `ovs/entrypoint.sh` inside the single `ovs` container):

- `br0` (Open vSwitch bridge, `datapath_type=netdev`, `stp_enable=true`)
  - `h1` — access port, VLAN 10, `192.168.10.1/24`
  - `h3` — access port, VLAN 20, `192.168.10.3/24` (same IP subnet as `h1`, on purpose — an isolation test across different subnets would fail with "network unreachable" from routing, not from VLAN isolation; using the same subnet makes this a genuine L2/ARP-level test)
- `br1` (same OVS settings)
  - `h2` — access port, VLAN 10, `192.168.10.2/24`
- `trunk-br0` / `trunk-br1` — a veth pair wired as an 802.1Q trunk port on each bridge (`trunk=10,20`), carrying both VLANs between the two switches

`h1`, `h2`, `h3` are Linux network namespaces created inside the `ovs`
container rather than separate Docker containers — see the README's
"Engineering notes" for why.

## Spanning-tree forward delay

Bringing the topology up and testing immediately fails: every port starts in
STP's `listening` then `learning` state and only reaches `forwarding` after
two forward-delay intervals (`stp-fwd-delay 15s` each, ~30-35s total).
`ovs-appctl stp/show br0` shows the state transition live. The run-book
documents this so a real "why can't these hosts talk yet" incident is not
mistaken for a misconfiguration.

## Test 1 — same VLAN, across the trunk (expect success)

```
$ docker compose exec ovs ip netns exec h1 ping -c 3 -W 2 192.168.10.2
PING 192.168.10.2 (192.168.10.2) 56(84) bytes of data.
64 bytes from 192.168.10.2: icmp_seq=1 ttl=64 time=0.320 ms
64 bytes from 192.168.10.2: icmp_seq=2 ttl=64 time=0.529 ms
64 bytes from 192.168.10.2: icmp_seq=3 ttl=64 time=0.452 ms

--- 192.168.10.2 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2035ms
```

`h1` (VLAN 10, `br0`) reaches `h2` (VLAN 10, `br1`) across the inter-switch
trunk. This is the trunk doing its job: extending one VLAN across two
switches over a single tagged link.

## Test 2 — different VLAN, same switch, same subnet (expect isolation)

```
$ docker compose exec ovs ip netns exec h1 ping -c 3 -W 2 192.168.10.3
PING 192.168.10.3 (192.168.10.3) 56(84) bytes of data.
From 192.168.10.1 icmp_seq=1 Destination Host Unreachable
From 192.168.10.1 icmp_seq=2 Destination Host Unreachable
From 192.168.10.1 icmp_seq=3 Destination Host Unreachable

--- 192.168.10.3 ping statistics ---
3 packets transmitted, 0 received, +3 errors, 100% packet loss, time 2059ms
```

`h1` (VLAN 10) cannot reach `h3` (VLAN 20) even though they share the same
`192.168.10.0/24` subnet and the same physical bridge (`br0`) — VLAN tagging
alone provides the isolation, with no IP-level routing involved.
