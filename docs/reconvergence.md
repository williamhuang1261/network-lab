# Measured OSPF reconvergence under fault injection

Produced by `faults/netem_test.sh` against the live r1<->r2 OSPF link, using
`tc netem` on r1's interface. Three conditions, three full runs. Real
numbers below, not a stated target.

## Method

- **Latency (100ms)** and **packet loss (20%)** are both well within OSPF's
  dead-timer tolerance (default 40s, with hellos every 10s), so the correct
  and expected result is that the adjacency stays `Full` -- these two
  conditions measure the real effect (RTT, loss rate) rather than a
  reconvergence time, since there is no reconvergence to measure.
- **Full link failure (100% loss)** does cause reconvergence. This is
  measured with a single `docker compose exec` session polling from inside
  r1 in a loop, timestamped with the container's own clock -- an earlier
  attempt that polled via repeated separate `docker compose exec` calls from
  the host measured 570s for a change that should take ~40s; that number was
  host exec overhead under load, not OSPF, and was discarded once the
  methodology was fixed (see the README's engineering notes).

## Condition 1: 100ms latency (adjacency survives, as expected)

| Run | Ping RTT (min/avg/max) | OSPF state after injection |
| --- | --- | --- |
| 1 | 100.912 / 105.169 / 111.128 ms | Full |
| 2 | 101.592 / 104.585 / 107.809 ms | Full |

## Condition 2: 20% packet loss (adjacency survives, as expected)

| Run | Ping loss observed | OSPF state after injection |
| --- | --- | --- |
| 1 | 25% (20 sent, 15 received) | Full |
| 2 | 20% (20 sent, 16 received) | Full |

The observed ping loss tracks the injected 20% reasonably closely (some
variance expected from a 20-packet sample).

## Condition 3: full link failure (100% loss) - measured reconvergence

| Run | Down-detection time | Reconvergence time (after restore) |
| --- | --- | --- |
| 1 | 42s | 10s |
| 2 | 35s | 19s |
| 3 | 124s | 11s |

**Down-detection:** min 35s, median 42s, max 124s.
**Reconvergence:** min 10s, median 11s, max 19s.

Down-detection clusters near the 40s default dead timer for two of three
runs (35s, 42s), consistent with FRR's own claimed behavior. The third run
(124s) is a real outlier, not discarded: this machine was running several
concurrent Claude Code sessions and their own Docker workloads at the time,
and OSPF's dead-timer processing itself runs on FRR's own scheduler inside
the container -- if the host was CPU-constrained enough to delay that
scheduler, a slower-than-normal dead-timer firing is a real, if unflattering,
possible cause, not a measurement artifact this time (the single-exec-session
method removes the *host-exec* overhead that caused the earlier 570s
artifact, but cannot remove genuine CPU contention affecting FRR itself).
Reconvergence-after-restore (10-19s) is consistent across all three runs and
matches the ~10s hello interval plus DR/BDR election and SPF recalculation.
