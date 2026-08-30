# Topology

```mermaid
graph LR
    subgraph L3["Layer 3 -- FRRouting"]
        r1["r1<br/>lo 10.0.0.1/32<br/>OSPF area 0"]
        r2["r2<br/>lo 10.0.0.2/32<br/>OSPF area 0 + eBGP AS65002"]
        r3["r3<br/>lo 10.0.0.3/32<br/>eBGP AS65003"]
        r1 -- "OSPF adjacency<br/>10.0.12.0/29" --> r2
        r2 -- "eBGP session<br/>10.0.23.0/29<br/>redistribute ospf" --> r3
    end

    subgraph L2["Layer 2 -- Open vSwitch (single ovs container)"]
        br0["br0<br/>STP enabled"]
        br1["br1<br/>STP enabled"]
        h1["h1<br/>VLAN 10<br/>192.168.10.1"]
        h3["h3<br/>VLAN 20<br/>192.168.10.3"]
        h2["h2<br/>VLAN 10<br/>192.168.10.2"]
        h1 -- access --> br0
        h3 -- access --> br0
        br0 -- "802.1Q trunk<br/>VLANs 10,20" --> br1
        h2 -- access --> br1
    end

    subgraph MON["Monitoring"]
        prom["Prometheus"]
        graf["Grafana :3000"]
        prom --> graf
    end

    r1 -.snmp/frr_exporter.-> prom
    r2 -.snmp/frr_exporter.-> prom
    r3 -.snmp/frr_exporter.-> prom
```

- **r1 <-> r2**: OSPF full adjacency over a point-to-point Docker network.
  Both routers advertise their loopback into area 0.
- **r2 <-> r3**: eBGP session (AS 65002 <-> AS 65003). r2 redistributes its
  OSPF-learned routes into BGP, so r3 learns r1's loopback without ever
  running OSPF itself — a genuine inter-domain redistribution boundary, not
  two protocols glued together for show.
- **br0 <-> br1**: an 802.1Q trunk between two Open vSwitch bridges carrying
  VLANs 10 and 20. `h1`/`h2` (VLAN 10) reach each other across the trunk;
  `h3` (VLAN 20, same switch and same IP subnet as `h1`) cannot reach either,
  proven by ARP-level isolation, not a routing failure.
- **Monitoring**: `snmp_exporter` polls each router's `snmpd` for interface
  counters; `frr_exporter` reads each router's vtysh unix sockets directly
  for OSPF/BGP protocol state. Both feed Prometheus, visualized in Grafana.
