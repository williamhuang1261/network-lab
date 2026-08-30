"""Unit tests for cross_check.py's text-parsing functions.

Tests the pure functions extracted in this same extension
(`parse_decoder_log`, `parse_frr_ospf_full`, `parse_frr_bgp_established`),
not `main()` itself -- `main()` shells out to a live `docker compose`
stack and is exercised end to end by actually running `cross_check.py`
against the topology, the same way it always has been, not by this suite.

The decoder-log samples below are the real lines this project's decoder
prints on a genuine agreeing run, taken verbatim from
`docs/decoder_verification.md`. The FRR `vtysh` samples are synthetic rows
built to the same column layout `parse_frr_ospf_full`/
`parse_frr_bgp_established` were written against -- not a literal capture --
since the exact whitespace of a live `vtysh` dump depends on hostname/AS
column widths that vary run to run.
"""
from cross_check import parse_decoder_log, parse_frr_bgp_established, parse_frr_ospf_full

REAL_AGREEING_DECODER_LOG = (
    "decoder: OSPF 10.0.0.1 <-> 10.0.0.2: inferred FULL (2-Way via mutual "
    "Hello + LS-Update observed from ['10.0.0.1', '10.0.0.2'])\n"
    "decoder: BGP 10.0.23.2 <-> 10.0.23.3: inferred ESTABLISHED (OPEN + "
    "KEEPALIVE observed from both sides)"
)


class TestParseDecoderLog:
    def test_real_agreeing_run_reports_both_full_and_established(self):
        assert parse_decoder_log(REAL_AGREEING_DECODER_LOG) == (True, True)

    def test_empty_log_reports_neither(self):
        assert parse_decoder_log("") == (False, False)

    def test_ospf_only_log_does_not_report_bgp(self):
        log = "decoder: OSPF 10.0.0.1 <-> 10.0.0.2: inferred FULL (...)"
        assert parse_decoder_log(log) == (True, False)


class TestParseFrrOspfFull:
    def test_full_dr_state_is_full(self):
        row = "10.0.0.2  1  Full/DR  25.122s  34.884s  10.0.12.3  eth1:10.0.12.2  0 0 0"
        assert parse_frr_ospf_full(row) is True

    def test_two_way_state_is_not_full(self):
        row = "10.0.0.2  1  2-Way/DROther  25.122s  34.884s  10.0.12.3  eth1:10.0.12.2  0 0 0"
        assert parse_frr_ospf_full(row) is False

    def test_no_neighbors_at_all_is_not_full(self):
        assert parse_frr_ospf_full("") is False


class TestParseFrrBgpEstablished:
    def test_established_row_with_pfxrcd_pfxsnt_before_na_is_established(self):
        # Established peers carry two more numeric columns before the
        # trailing N/A in this deployment's FRR version.
        row = "10.0.23.3  4  65003  19  14  0  0  0  00:00:29  5  3  N/A"
        assert parse_frr_bgp_established(row) is True

    def test_active_state_is_not_established(self):
        row = "10.0.23.3  4  65003  19  14  0  0  0  00:00:29  Active"
        assert parse_frr_bgp_established(row) is False

    def test_idle_state_is_not_established(self):
        row = "10.0.23.3  4  65003  0  0  0  0  0  never  Idle"
        assert parse_frr_bgp_established(row) is False

    def test_no_peers_at_all_is_not_established(self):
        assert parse_frr_bgp_established("") is False
