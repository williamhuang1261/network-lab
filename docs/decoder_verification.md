# Independent decoder vs. FRR's own reported state

Produced by `decoder/cross_check.py`, which triggers a fresh OSPF/BGP
handshake, lets the independent Scapy-based decoder (`decoder/ospf_bgp_decoder.py`)
observe it from the wire, and separately queries FRR's own `vtysh` for the
same routers at the same moment. Two real runs, both agreeing.

## Run 1

```
decoder: OSPF 10.0.0.1 <-> 10.0.0.2: inferred FULL (2-Way via mutual Hello + LS-Update observed from ['10.0.0.1', '10.0.0.2'])
decoder: BGP 10.0.23.2 <-> 10.0.23.3: inferred ESTABLISHED (OPEN + KEEPALIVE observed from both sides)

FRR (r1, show ip ospf neighbor):
10.0.0.2  1  Full/DR  25.122s  34.884s  10.0.12.3  eth1:10.0.12.2  0 0 0

FRR (r2, show ip bgp summary):
10.0.23.3  4  65003  19  14  0  0  0  00:00:29  N/A

Verdict:
OSPF: decoder says Full=True, FRR says Full=True -> AGREE
BGP:  decoder says Established=True, FRR says Established=True -> AGREE
```

## Run 2

```
FRR (r2, show ip bgp summary):
10.0.23.3  4  65003  32  25  0  0  0  00:00:28  N/A

Verdict:
OSPF: decoder says Full=True, FRR says Full=True -> AGREE
BGP:  decoder says Established=True, FRR says Established=True -> AGREE
```

## What this does and does not prove

It proves that a decoder with **no access to FRR's config, state files, or
control sockets** -- only raw packets captured off r2's own interfaces --
independently reaches the same conclusion FRR itself reports via `vtysh`,
for both OSPF and BGP, across two separate real handshakes. That is
meaningful black-box verification: FRR is not just claiming Full/Established,
its own protocol traffic on the wire is consistent with that claim.

It does **not** prove the decoder's inference criteria are equivalent to
RFC 2328/4271's exact state machines bit-for-bit -- they are deliberately
looser, documented honestly in `ospf_bgp_decoder.py`'s own docstring (2-Way
+ LS-Update-from-either-side for OSPF, not the stricter DBD-M-bit-clear
signal that was tried first and abandoned; OPEN+KEEPALIVE-from-both-sides
for BGP, which does match RFC 4271's actual Established criterion). Two
agreeing runs is evidence, not proof across every possible failure mode --
a decoder that always reported "agree" regardless of actual state would
also look identical to Run 1 and Run 2. The honest claim is: this decoder,
built independently, reached the correct conclusion on two real, freshly
triggered handshakes, using only what it could observe on the wire.
