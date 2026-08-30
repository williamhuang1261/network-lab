"""Cross-checks the independent packet decoder against FRR's own state.

Runs from the host (like faults/netem_test.sh), not inside the decoder
container: the decoder image deliberately stays a small Python+Scapy image
with no `vtysh` binary or FRR control-socket volume mount, since it doesn't
need either to do its job. This script drives both sides from outside:
starts the decoder container, triggers a fresh OSPF/BGP handshake so there
is something for the decoder to observe, then compares the decoder's
inferred conclusion (from its container logs) against FRR's own `vtysh`
output for the same routers, and prints an honest agree/disagree verdict --
including if they disagree, which would be the actually interesting result.
"""
import re
import subprocess
import sys
import time

COMPOSE = ["docker", "compose"]


def run(cmd: list, timeout: int = 20) -> str:
    result = subprocess.run(
        cmd, capture_output=True, text=True, timeout=timeout, cwd="."
    )
    return result.stdout + result.stderr


def main() -> None:
    print("=== restarting decoder for a clean capture window ===")
    run(COMPOSE + ["up", "-d", "decoder"])
    time.sleep(3)

    print("=== triggering a fresh OSPF/BGP handshake ===")
    run(COMPOSE + ["exec", "-T", "r1", "vtysh", "-c", "clear ip ospf process"])
    run(COMPOSE + ["exec", "-T", "r2", "vtysh", "-c", "clear ip bgp *"])

    print("=== waiting 30s for the decoder to observe it ===")
    time.sleep(30)

    decoder_log = run(COMPOSE + ["logs", "decoder"], timeout=15)
    print(decoder_log)

    decoder_ospf_full = bool(re.search(r"inferred FULL", decoder_log))
    decoder_bgp_established = bool(re.search(r"inferred ESTABLISHED", decoder_log))

    print("=== FRR's own reported state ===")
    frr_ospf = run(COMPOSE + ["exec", "-T", "r1", "vtysh", "-c", "show ip ospf neighbor"])
    print(frr_ospf)
    frr_bgp = run(COMPOSE + ["exec", "-T", "r2", "vtysh", "-c", "show ip bgp summary"])
    print(frr_bgp)

    frr_ospf_full = "Full" in frr_ospf
    frr_bgp_established = bool(re.search(r"\d+:\d+:\d+\s+\d+\s+\d+\s+N/A", frr_bgp))

    print("=== verdict ===")
    ospf_agree = decoder_ospf_full == frr_ospf_full
    bgp_agree = decoder_bgp_established == frr_bgp_established

    print(
        f"OSPF: decoder says Full={decoder_ospf_full}, FRR says Full={frr_ospf_full} "
        f"-> {'AGREE' if ospf_agree else 'DISAGREE'}"
    )
    print(
        f"BGP: decoder says Established={decoder_bgp_established}, "
        f"FRR says Established={frr_bgp_established} "
        f"-> {'AGREE' if bgp_agree else 'DISAGREE'}"
    )

    if not (ospf_agree and bgp_agree):
        sys.exit(1)


if __name__ == "__main__":
    main()
