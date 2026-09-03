# Why the RDMA lab runs in a Lima VM, and why the benchmark topology differs from setup.sh's

Two separate infrastructure findings, made while building this extension,
each stated plainly rather than worked around silently.

## 1. Why a Lima VM instead of Docker Compose

Every other component in this repo runs as a Docker Compose service. RDMA
does not, because Docker Desktop's LinuxKit VM cannot load kernel modules at
all -- confirmed directly:

```
docker run --rm --privileged --net=host alpine modprobe rdma_rxe
modprobe: FATAL: Module rdma_rxe not found in directory /lib/modules/6.12.76-linuxkit
```

`find /lib/modules` from inside the same privileged container returns "No
such file or directory" -- there is no modules directory to search, not just
a missing module. This is the same underlying limit that ruled out
containerlab for this repo's routing lab in the first place (see the
containerlab note in `../README.md`'s engineering notes): Docker Desktop's VM
boundary hides the real Linux kernel from what a privileged container can
touch.

`sensor-pipeline` (this registry's kernel character-device project) hit an
equivalent problem and solved it by running its kernel module inside a Lima
Ubuntu VM instead of Docker Desktop. The same fix applies here, verified
before committing to it:

```
limactl shell default -- sudo modprobe rdma_rxe
limactl shell default -- lsmod | grep rdma
# rdma_rxe, ib_uverbs, ib_core all present
```

So `rdma/setup.sh` and `rdma/bench.sh` run inside that Lima VM
(`limactl shell default -- bash rdma/setup.sh`), not as new Docker Compose
services.

## 2. Why `bench.sh` doesn't benchmark `setup.sh`'s namespace pair

`rdma/setup.sh` creates two real soft-RoCE devices, `rxe0` and `rxe1`, bound
to a veth pair that crosses two network namespaces (`rdma-a`, `rdma-b`).
Both come up `PORT_ACTIVE`, and plain ICMP between them works:

```
sudo ip netns exec rdma-a ping -c2 192.168.100.2
# 2 packets transmitted, 2 received, 0% packet loss
```

RDMA data-plane traffic across that same link does not. Every attempt with
`ib_write_bw` fails identically:

```
Completion with error at client
Failed status 5: wr_id 0 syndrom 0x0
```

Status 5 is `WR_FLUSH_ERR`. This is not a message-size or segmentation
problem -- it reproduces on a single 64-byte, single-iteration write, not
just the default 64KB/5000-iteration run. Four topology variants were tried
to isolate the cause before accepting it as a real constraint:

| Topology | Result |
| --- | --- |
| `rxe0`/`rxe1` across two netns, joined by veth | ICMP works, RDMA write fails (`WR_FLUSH_ERR`) |
| Same veth pair, both ends left in the root namespace (no netns crossing) | ICMP itself fails ("Destination Host Unreachable") |
| The above, bridged through a Linux bridge instead of a raw veth-to-veth link | Same as above -- ICMP fails |
| Two macvlan/ipvlan siblings on the VM's real NIC | ICMP fails -- the VZ hypervisor's virtio-net backend doesn't support the L2 hairpin sibling interfaces need |
| A single `rxe` device bound to the VM's real NIC, looped back to its own IP | **Works** -- real RDMA write/read/latency traffic, verified with actual `ib_write_bw`/`ib_read_bw`/`ib_write_lat` runs |

Only the last row carries RDMA traffic in this VM. `rdma/bench.sh` therefore
benchmarks that loopback topology, and `docs/rdma-results.md` states the
scoping explicitly: the measured numbers are a real RDMA data path (real
queue pairs, real memory registration, real one-sided write/read verbs) but
not a two-namespace one. `rdma/setup.sh`'s namespace pair remains useful on
its own terms -- it demonstrates binding independent soft-RoCE devices to
separate network namespaces, a real RDMA/netns interaction -- it just isn't
what the bandwidth numbers measure.

## What would change this

If a future iteration reproduces this on a different kernel or hypervisor
(a bare-metal Linux host, or a VM backend other than macOS's
Virtualization.framework/VZ), the veth data-plane failure is worth
re-testing -- it may be specific to this kernel build or virtio-net
implementation rather than a fundamental veth+rxe incompatibility, and this
document's scope note should be revisited rather than left stale.
