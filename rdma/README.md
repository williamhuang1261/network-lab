# RDMA lab (soft-RoCE)

Two Linux network namespaces, `rdma-a` and `rdma-b`, joined by a veth pair,
each running a software RoCE (`rxe`) RDMA device bound to its veth end. Real
RDMA verbs semantics (queue pairs, memory registration, one-sided read/write)
without a physical RDMA NIC.

This does **not** run under this repo's Docker Compose stack -- see
[`../docs/rdma.md`](../docs/rdma.md) for why, and how to run it in a Lima VM
instead.

## Running it

Inside a Linux VM with kernel-module support (tested in Lima's `default` VM):

```
sudo apt-get install -y rdma-core ibverbs-providers ibverbs-utils perftest
bash rdma/setup.sh
```

`setup.sh` loads `rdma_rxe`, creates the namespace/veth pair, and binds
`rxe0`/`rxe1`. It prints `ibv_devinfo` for both devices; look for
`state: PORT_ACTIVE (4)` on each.

Run the bandwidth/latency benchmarks with `rdma/bench.sh` (see
[`../docs/rdma-results.md`](../docs/rdma-results.md) for real recorded
output).

Tear down with:

```
bash rdma/teardown.sh
```
