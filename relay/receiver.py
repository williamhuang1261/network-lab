"""Receives length-prefixed data frames over TCP and counts them.

Wire protocol: each frame is a 4-byte big-endian unsigned length, followed
by that many bytes of payload. No compression, no encryption -- the point
of this module is the transport and framing, not the payload format.
"""
import os
import socket
import struct
import sys
import time

from metrics import counter_inc, gauge_set, start_metrics_server

HOST = "0.0.0.0"
PORT = 9500
METRICS_PORT = int(os.environ.get("METRICS_PORT", "9600"))
HEADER = struct.Struct(">I")


def recv_exact(conn: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("peer closed mid-frame")
        buf.extend(chunk)
    return bytes(buf)


def serve() -> None:
    start_metrics_server(METRICS_PORT)
    print(f"[receiver] metrics on :{METRICS_PORT}/metrics", flush=True)

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((HOST, PORT))
    listener.listen(1)
    print(f"[receiver] listening on {HOST}:{PORT}", flush=True)

    frames_total = 0
    bytes_total = 0

    while True:
        conn, addr = listener.accept()
        print(f"[receiver] connection from {addr}", flush=True)
        try:
            with conn:
                while True:
                    header = recv_exact(conn, HEADER.size)
                    (length,) = HEADER.unpack(header)
                    payload = recv_exact(conn, length)
                    frames_total += 1
                    bytes_total += length
                    counter_inc(
                        "relay_frames_received_total",
                        "Total frames received by the relay.",
                    )
                    counter_inc(
                        "relay_bytes_received_total",
                        "Total payload bytes received by the relay.",
                        length,
                    )
                    gauge_set(
                        "relay_last_frame_timestamp_seconds",
                        "Unix timestamp the last frame was received.",
                        time.time(),
                    )
                    if frames_total % 10 == 0:
                        print(
                            f"[receiver] frames={frames_total} bytes={bytes_total} "
                            f"last_payload={payload[:32]!r}",
                            flush=True,
                        )
        except ConnectionError as exc:
            print(f"[receiver] connection lost: {exc}", flush=True)
            time.sleep(0.5)


if __name__ == "__main__":
    sys.exit(serve())
