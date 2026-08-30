"""Unit tests for the decoder's OSPF/BGP state-inference rules.

Drives `handle_ospf`/`handle_bgp` directly with synthetic Scapy packets --
no live capture, no Docker Compose stack. This tests the exact rules the
module's own docstring documents: OSPF needs mutual Hello (2-Way) plus an
LS-Update from either side; BGP needs OPEN followed by KEEPALIVE from
*both* sides. `handle_ospf`/`handle_bgp` track state in module-level dicts
across calls by design (that's how the live decoder tracks a capture
window), so every test resets that state first rather than relying on
test ordering.
"""
import pytest
from scapy.contrib.bgp import BGPHeader, BGPKeepAlive, BGPOpen
from scapy.contrib.ospf import OSPF_Hdr, OSPF_Hello, OSPF_LSUpd
from scapy.layers.inet import IP, TCP

import ospf_bgp_decoder as decoder


@pytest.fixture(autouse=True)
def reset_decoder_state():
    decoder.ospf_hello_neighbors.clear()
    decoder.ospf_lsupdate_seen.clear()
    decoder.ospf_full_reported.clear()
    decoder.bgp_open_seen.clear()
    decoder.bgp_keepalive_after_open.clear()
    decoder.bgp_established_reported.clear()
    yield


def ospf_hello(src: str, neighbors: list[str]):
    return OSPF_Hdr(src=src) / OSPF_Hello(router=src, neighbors=neighbors)


def ospf_lsupdate(src: str):
    return OSPF_Hdr(src=src) / OSPF_LSUpd()


def bgp_pkt(src: str, dst: str, msg):
    return IP(src=src, dst=dst) / TCP(sport=179, dport=54321) / BGPHeader() / msg


def bgp_open(my_as: int, bgp_id: str):
    return BGPOpen(my_as=my_as, hold_time=180, bgp_id=bgp_id)


class TestOspfFullInference:
    def test_mutual_hello_alone_is_not_full(self):
        decoder.handle_ospf(ospf_hello("10.0.0.1", ["10.0.0.2"]))
        decoder.handle_ospf(ospf_hello("10.0.0.2", ["10.0.0.1"]))

        assert decoder.ospf_full_reported == set()

    def test_one_sided_hello_is_not_full_even_with_lsupdate(self):
        # Only 10.0.0.1 has heard from 10.0.0.2 -- not a mutual 2-Way yet.
        decoder.handle_ospf(ospf_hello("10.0.0.1", ["10.0.0.2"]))
        decoder.handle_ospf(ospf_lsupdate("10.0.0.1"))

        assert decoder.ospf_full_reported == set()

    def test_two_way_plus_lsupdate_from_either_side_is_full(self):
        decoder.handle_ospf(ospf_hello("10.0.0.1", ["10.0.0.2"]))
        decoder.handle_ospf(ospf_hello("10.0.0.2", ["10.0.0.1"]))
        decoder.handle_ospf(ospf_lsupdate("10.0.0.1"))
        # The mutual Hello already happened; a fresh Hello re-triggers the check.
        decoder.handle_ospf(ospf_hello("10.0.0.2", ["10.0.0.1"]))

        assert decoder.ospf_full_reported == {frozenset({"10.0.0.1", "10.0.0.2"})}

    def test_lsupdate_from_only_one_router_is_enough(self):
        # The module's documented rule is "either side", not "both sides".
        decoder.handle_ospf(ospf_hello("10.0.0.1", ["10.0.0.2"]))
        decoder.handle_ospf(ospf_lsupdate("10.0.0.2"))
        decoder.handle_ospf(ospf_hello("10.0.0.2", ["10.0.0.1"]))

        assert decoder.ospf_full_reported == {frozenset({"10.0.0.1", "10.0.0.2"})}


class TestBgpEstablishedInference:
    def test_open_alone_is_not_established(self):
        decoder.handle_bgp(bgp_pkt("10.0.0.1", "10.0.0.2", bgp_open(65001, "10.0.0.1")))

        assert decoder.bgp_established_reported == set()

    def test_keepalive_from_only_one_side_is_not_established(self):
        decoder.handle_bgp(bgp_pkt("10.0.0.1", "10.0.0.2", bgp_open(65001, "10.0.0.1")))
        decoder.handle_bgp(bgp_pkt("10.0.0.1", "10.0.0.2", BGPKeepAlive()))

        assert decoder.bgp_established_reported == set()

    def test_keepalive_from_both_sides_is_established(self):
        decoder.handle_bgp(bgp_pkt("10.0.0.1", "10.0.0.2", bgp_open(65001, "10.0.0.1")))
        decoder.handle_bgp(bgp_pkt("10.0.0.1", "10.0.0.2", BGPKeepAlive()))
        decoder.handle_bgp(bgp_pkt("10.0.0.2", "10.0.0.1", bgp_open(65002, "10.0.0.2")))
        decoder.handle_bgp(bgp_pkt("10.0.0.2", "10.0.0.1", BGPKeepAlive()))

        assert decoder.bgp_established_reported == {frozenset({"10.0.0.1", "10.0.0.2"})}

    def test_keepalive_before_open_on_that_side_does_not_count(self):
        # A KEEPALIVE seen before that side's own OPEN must not satisfy the
        # "KEEPALIVE after OPEN" requirement.
        decoder.handle_bgp(bgp_pkt("10.0.0.2", "10.0.0.1", BGPKeepAlive()))
        decoder.handle_bgp(bgp_pkt("10.0.0.1", "10.0.0.2", bgp_open(65001, "10.0.0.1")))
        decoder.handle_bgp(bgp_pkt("10.0.0.1", "10.0.0.2", BGPKeepAlive()))
        decoder.handle_bgp(bgp_pkt("10.0.0.2", "10.0.0.1", bgp_open(65002, "10.0.0.2")))

        assert decoder.bgp_established_reported == set()
