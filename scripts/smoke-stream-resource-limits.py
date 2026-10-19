#!/usr/bin/env python3
"""Verify a patched, production-signed macOS stream without sending input events.

uv run --no-project scripts/smoke-stream-resource-limits.py --binary /path/to/guiport
Raw captures remain in a private temporary directory; stdout contains metrics.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib")


def footprint(pid: int) -> int:
    data = ctypes.create_string_buffer(1024)
    if LIBPROC.proc_pid_rusage(pid, 0, ctypes.byref(data)) != 0:
        return 0
    return ctypes.c_uint64.from_buffer(data, 72).value


def group_footprint(group: int) -> int:
    rows = subprocess.check_output(["ps", "-axo", "pid=,pgid="], text=True)
    return sum(footprint(int(pid)) for pid, pgid in (row.split() for row in rows.splitlines())
               if int(pgid) == group)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--soak-seconds", type=int, default=15, choices=range(1, 61))
    options = parser.parse_args()
    binary = str(Path(options.binary).resolve())
    root = Path(tempfile.mkdtemp(prefix="guiport-stream-safety-"))
    results: list[dict[str, object]] = []

    def run(name: str, arguments: list[str], expected: int = 0, blocked: bool = False) -> None:
        log = root / f"{name}.ndjson"
        error_log = root / f"{name}.err"
        read_fd = write_fd = None
        with log.open("wb") as output, error_log.open("wb") as errors:
            if blocked:
                read_fd, write_fd = os.pipe()
                os.set_blocking(write_fd, False)
                try:
                    while True:
                        os.write(write_fd, b"x" * 4096)
                except BlockingIOError:
                    pass
                os.set_blocking(write_fd, True)
            start = time.monotonic()
            child = subprocess.Popen([binary, "stream", *arguments, "-o", str(root / f"{name}.png")],
                                     stdout=write_fd if blocked else output, stderr=errors,
                                     start_new_session=True)
            peak = 0
            try:
                while child.poll() is None:
                    peak = max(peak, group_footprint(child.pid))
                    assert peak < 384 * 1024**2, f"{name}: exceeded external 384 MiB ceiling"
                    assert time.monotonic() - start < options.soak_seconds + 10, f"{name}: hung"
                    time.sleep(0.05)
                code = child.wait(timeout=2)
            finally:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                if write_fd is not None:
                    os.close(write_fd)
                    os.close(read_fd)
            elapsed = time.monotonic() - start
        assert code == expected, f"{name}: exit {code}; {error_log.read_text()[:500]}"
        events = [] if blocked else [json.loads(line) for line in log.read_text().splitlines()]
        frames = [event for event in events if event["event"] == "frame"]
        if not blocked:
            assert events[-1]["event"] == "stopped", f"{name}: no clean stop event"
            assert all(frame["width"] * frame["height"] <= 8_294_400 for frame in frames)
            assert Path(root / f"{name}.png").exists() if frames else True
            if "--frames" in arguments:
                wanted = int(arguments[arguments.index("--frames") + 1])
                assert len(frames) == wanted, f"{name}: expected {wanted} frames, received {len(frames)}"
            if name == "fast-stream":
                assert frames, "High-rate capture produced no frames"
        result = {"test": name, "exit": code, "seconds": round(elapsed, 3), "frames": len(frames),
                  "peak_group_physical_MiB": round(peak / 1024**2, 2)}
        results.append(result)
        print(json.dumps(result), flush=True)

    run("one-frame", ["--frames", "1", "--seconds", "5"])
    run("idle-deadline", ["--fps", "0.1", "--seconds", "2"])
    run("fast-stream", ["--fps", "60", "--seconds", str(options.soak_seconds)])
    run("bounded-archive", ["--frames", "3", "--seconds", "5", "--frames-dir", str(root / "frames")])
    run("blocked-consumer", ["--seconds", "0.25"], expected=75, blocked=True)
    (root / "metrics.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
