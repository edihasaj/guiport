#!/usr/bin/env python3
"""Check a running patched daemon's request limits without sending input events.

Run with `uv run --no-project scripts/smoke-daemon-resource-limits.py`.
The incomplete-request check occupies the daemon's accept loop for five seconds.
"""
import errno
import json
from pathlib import Path
import socket
import time

ADDRESS = str(Path.home() / ".guiport/agent.sock")


def connect() -> socket.socket:
    client = socket.socket(socket.AF_UNIX)
    client.settimeout(2)
    client.connect(ADDRESS)
    return client


def main() -> None:
    with connect() as client:
        try:
            client.sendall(b"x" * (1_048_576 + 8192))
            client.shutdown(socket.SHUT_WR)
            closed = client.recv(1) == b""
        except OSError as error:
            if error.errno not in (errno.EPIPE, errno.ECONNRESET, errno.ENOTCONN):
                raise
            closed = True
    assert closed, "Oversized request was not rejected"

    start = time.monotonic()
    with connect() as client:
        client.sendall(b"x")
        time.sleep(4.5)
        client.sendall(b"x")
        client.settimeout(1.5)
        assert client.recv(1) == b"", "Incomplete request did not expire"
    elapsed = time.monotonic() - start
    assert elapsed < 6, f"Slow client extended the deadline: {elapsed}"

    with connect() as client:
        client.shutdown(socket.SHUT_WR)
        assert client.recv(1) == b"", "Daemon did not recover after malformed requests"
    print(json.dumps({"oversized_request": "rejected", "slow_request_seconds": round(elapsed, 3),
                      "daemon_accept_loop": "responsive", "input_events_sent": 0}))


if __name__ == "__main__":
    main()
