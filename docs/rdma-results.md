# RDMA benchmark results

Real, captured output from `rdma/bench.sh`, run inside the Lima `default`
Ubuntu VM (kernel `7.0.0-28-generic`) against a single soft-RoCE (`rxe`)
device bound to the VM's own NIC (`eth0`, self-loopback -- see
[`rdma.md`](rdma.md) for why this topology, not the `rxe0`/`rxe1` pair
`setup.sh` creates across two network namespaces). 64KB messages for
bandwidth, 2-byte messages for latency, `--report_gbits`. Three trials each,
min/median/max reported rather than a single cherry-picked run, matching
this project's existing standard in [`reconvergence.md`](reconvergence.md).

## RDMA write bandwidth (`ib_write_bw`)

| Trial | BW peak (Gb/s) | BW average (Gb/s) |
| --- | --- | --- |
| 1 | 9.17 | 8.57 |
| 2 | 10.26 | 8.68 |
| 3 | 9.38 | 8.74 |

BW average: min 8.57, median 8.68, max 8.74 Gb/s.

## RDMA read bandwidth (`ib_read_bw`)

| Trial | BW peak (Gb/s) | BW average (Gb/s) |
| --- | --- | --- |
| 1 | 6.96 | 6.96 |
| 2 | 6.83 | 6.82 |
| 3 | 7.14 | 7.13 |

BW average: min 6.82, median 6.96, max 7.13 Gb/s.

## RDMA write latency (`ib_write_lat`, 2-byte payload)

| Trial | t_avg (usec) | t_min (usec) | 99.9th pct (usec) |
| --- | --- | --- | --- |
| 1 | 2.56 | 1.10 | 13.08 |
| 2 | 2.90 | 1.10 | 21.15 |
| 3 | 2.72 | 1.10 | 16.85 |

t_avg: min 2.56, median 2.72, max 2.90 usec.

## Honest scoping

These numbers measure a real RDMA data path -- real queue pairs, real
memory registration, real one-sided write/read verbs, traversing the
kernel's actual RDMA and network stack via `rxe`, not a mocked or simulated
one. They do **not** measure RDMA traffic crossing the `rxe0`/`rxe1`
namespace pair `setup.sh` creates; that topology's RDMA data plane does not
work in this VM (see [`rdma.md`](rdma.md)), so all measured numbers here
come from a single device looped back to itself over the VM's real NIC.
