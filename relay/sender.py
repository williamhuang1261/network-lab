"""Streams length-prefixed data frames to the receiver over TCP.

Wire protocol: each frame is a 4-byte big-endian unsigned length, followed
by that many bytes of payload.
"""
import os
import socket
import struct
import sys
import time

from metrics import counter_inc, gauge_set, start_metrics_server

METRICS_PORT = int(os.environ.get("METRICS_PORT", "9600"))
RECEIVER_HOST = os.environ.get("RECEIVER_HOST", "10.0.3.3")
RECEIVER_PORT = int(os.environ.get("RECEIVER_PORT", "9500"))
FRAME_INTERVAL_SECONDS = float(os.environ.get("FRAME_INTERVAL_SECONDS", "0.5"))
CONNECT_TIMEOUT_SECONDS = float(os.environ.get("CONNECT_TIMEOUT_SECONDS", "3"))
# TCP_USER_TIMEOUT bounds how long unacknowledged data may sit before the
# kernel gives up and fails the write. Without this, sendall() on a
# mid-stream-broken path keeps "succeeding" into the local send buffer
# indefinitely (Linux's default retransmission timeout is minutes, not
# seconds) - the client would never notice the path died.
TCP_USER_TIMEOUT_MS = int(os.environ.get("TCP_USER_TIMEOUT_MS", "5000"))
INITIAL_BACKOFF_SECONDS = 0.5
MAX_BACKOFF_SECONDS = 10.0
HEADER = struct.Struct(">I")


def make_payload(seq: int) -> bytes:
    return f"frame-{seq}-{time.time():.3f}".encode()


def connect_with_retry() -> socket.socket:
    backoff = INITIAL_BACKOFF_SECONDS
    attempt = 0
    while True:
        attempt += 1
        try:
            conn = socket.create_connection(
                (RECEIVER_HOST, RECEIVER_PORT), timeout=CONNECT_TIMEOUT_SECONDS
            )
            conn.setsockopt(
                socket.IPPROTO_TCP, socket.TCP_USER_TIMEOUT, TCP_USER_TIMEOUT_MS
            )
            print(
                f"[sender] connected to {RECEIVER_HOST}:{RECEIVER_PORT} "
                f"(attempt {attempt})",
                flush=True,
            )
            return conn
        except OSError as exc:
            print(
                f"[sender] connect attempt {attempt} failed ({exc}); "
                f"retrying in {backoff:.1f}s",
                flush=True,
            )
            time.sleep(backoff)
            backoff = min(backoff * 2, MAX_BACKOFF_SECONDS)


def stream() -> None:
    start_metrics_server(METRICS_PORT)
    print(f"[sender] metrics on :{METRICS_PORT}/metrics", flush=True)

    seq = 0
    frames_since_connect = 0
    reconnect_count = 0
    while True:
        conn = connect_with_retry()
        frames_since_connect = 0
        try:
            with conn:
                while True:
                    payload = make_payload(seq)
                    conn.sendall(HEADER.pack(len(payload)) + payload)
                    seq += 1
                    frames_since_connect += 1
                    counter_inc(
                        "relay_frames_sent_total", "Total frames sent by the relay."
                    )
                    gauge_set(
                        "relay_reconnect_count",
                        "Number of times the sender has reconnected.",
                        reconnect_count,
                    )
                    if seq % 10 == 0:
                        print(
                            f"[sender] sent {seq} frames total "
                            f"(reconnects={reconnect_count})",
                            flush=True,
                        )
                    time.sleep(FRAME_INTERVAL_SECONDS)
        except OSError as exc:
            reconnect_count += 1
            print(
                f"[sender] send failed after {frames_since_connect} frames on "
                f"this connection ({exc}); reconnecting "
                f"(reconnect #{reconnect_count})",
                flush=True,
            )


if __name__ == "__main__":
    sys.exit(stream())
