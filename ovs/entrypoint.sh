#!/bin/bash
set -euo pipefail

mkdir -p /var/run/openvswitch

echo "[ovs] starting ovsdb-server and ovs-vswitchd (userspace/netdev datapath)"
/usr/share/openvswitch/scripts/ovs-ctl start --system-id=random --no-ovs-vswitchd
ovs-vswitchd --pidfile --detach --log-file -vconsole:info \
    unix:/var/run/openvswitch/db.sock

sleep 1

echo "[ovs] creating bridges br0 (VLAN 10 access: h1, VLAN 20 access: h3) and br1 (VLAN 10 access: h2)"
ovs-vsctl --may-exist add-br br0 -- set bridge br0 datapath_type=netdev stp_enable=true
ovs-vsctl --may-exist add-br br1 -- set bridge br1 datapath_type=netdev stp_enable=true

echo "[ovs] wiring an 802.1Q trunk link between br0 and br1, carrying VLANs 10 and 20"
ip link add trunk-br0 type veth peer name trunk-br1
ip link set trunk-br0 up
ip link set trunk-br1 up
ovs-vsctl --may-exist add-port br0 trunk-br0 -- set port trunk-br0 trunk=10,20
ovs-vsctl --may-exist add-port br1 trunk-br1 -- set port trunk-br1 trunk=10,20

create_host() {
    local ns="$1" bridge="$2" vlan="$3" veth_host="$4" veth_ns="$5" ip_cidr="$6"
    ip netns add "$ns" 2>/dev/null || true
    ip link add "$veth_host" type veth peer name "$veth_ns"
    ip link set "$veth_ns" netns "$ns"
    ip link set "$veth_host" up
    ip netns exec "$ns" ip link set lo up
    ip netns exec "$ns" ip link set "$veth_ns" up
    ip netns exec "$ns" ip addr add "$ip_cidr" dev "$veth_ns"
    ovs-vsctl --may-exist add-port "$bridge" "$veth_host" -- set port "$veth_host" tag="$vlan"
}

echo "[ovs] creating host network namespaces h1 (br0/VLAN10), h2 (br1/VLAN10), h3 (br0/VLAN20)"
create_host h1 br0 10 veth-h1 veth-h1-ns 192.168.10.1/24
create_host h2 br1 10 veth-h2 veth-h2-ns 192.168.10.2/24
create_host h3 br0 20 veth-h3 veth-h3-ns 192.168.10.3/24

echo "[ovs] topology ready"
ovs-vsctl show

exec sleep infinity
