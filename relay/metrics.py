"""A minimal Prometheus text-exposition server, stdlib only.

Not a general metrics library -- just enough to expose a handful of
monotonic counters and gauges as `/metrics`, in the same pattern every
other exporter in this stack already uses (snmp_exporter, frr_exporter).
"""
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_lock = threading.Lock()
_counters: dict[str, float] = {}
_gauges: dict[str, float] = {}
_help: dict[str, str] = {}


def counter_inc(name: str, help_text: str, amount: float = 1) -> None:
    with _lock:
        _counters[name] = _counters.get(name, 0) + amount
        _help.setdefault(name, help_text)


def gauge_set(name: str, help_text: str, value: float) -> None:
    with _lock:
        _gauges[name] = value
        _help.setdefault(name, help_text)


def _render() -> bytes:
    lines = []
    with _lock:
        for name, value in _counters.items():
            lines.append(f"# HELP {name} {_help[name]}")
            lines.append(f"# TYPE {name} counter")
            lines.append(f"{name} {value}")
        for name, value in _gauges.items():
            lines.append(f"# HELP {name} {_help[name]}")
            lines.append(f"# TYPE {name} gauge")
            lines.append(f"{name} {value}")
    return ("\n".join(lines) + "\n").encode()


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, *args) -> None:  # silence per-request logging
        pass

    def do_GET(self) -> None:
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        body = _render()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def start_metrics_server(port: int) -> None:
    server = ThreadingHTTPServer(("0.0.0.0", port), _Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
