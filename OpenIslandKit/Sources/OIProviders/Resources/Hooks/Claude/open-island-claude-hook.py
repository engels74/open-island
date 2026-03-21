#!/usr/bin/env python3
"""Open Island hook script for Claude Code.

Forwards hook events to the Open Island macOS app via Unix domain socket.
For blocking events (PermissionRequest, PreToolUse), waits for the app's decision.

Protocol:
    - Reads JSON from stdin (Claude Code hook event)
    - Connects to Unix domain socket at SOCKET_PATH
    - Sends event JSON followed by newline
    - For blocking events: reads decision JSON from socket, outputs to stdout
    - For all other events: outputs {} to stdout
    - Exit 0 on success; never blocks Claude Code on failure
"""

import json
import socket
import sys

SOCKET_PATH = "/tmp/open-island-claude.sock"

# Generous timeout for permission responses.
# The Swift app enforces its own 5-minute permission timeout.
PERMISSION_TIMEOUT_SECS = 600


def main() -> None:
    try:
        raw = sys.stdin.read()
    except Exception:
        _exit_ok()
        return

    try:
        event = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        _exit_ok()
        return

    hook_name = event.get("hook_event_name", "") if isinstance(event, dict) else ""
    is_blocking = hook_name in ("PermissionRequest", "PreToolUse")

    sock = _connect()
    if sock is None:
        _exit_ok()
        return

    try:
        _send(sock, raw)

        if is_blocking:
            response = _recv(sock)
            if response is not None:
                sys.stdout.write(response)
                sys.stdout.flush()
            else:
                _exit_ok()
        else:
            _exit_ok()
    except Exception:
        _exit_ok()
    finally:
        try:
            sock.close()
        except Exception:
            pass


def _connect() -> socket.socket | None:
    """Connect to the Open Island Unix domain socket. Returns None on failure."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(SOCKET_PATH)
        return sock
    except Exception:
        return None


def _send(sock: socket.socket, data: str) -> None:
    """Send JSON data followed by a newline delimiter."""
    payload = data.strip() + "\n"
    sock.sendall(payload.encode("utf-8"))


def _recv(sock: socket.socket) -> str | None:
    """Read a newline-delimited JSON response from the socket."""
    sock.settimeout(PERMISSION_TIMEOUT_SECS)
    buf = b""
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
            if b"\n" in buf:
                break
    except socket.timeout:
        return None
    except Exception:
        return None

    line = buf.split(b"\n", 1)[0]
    if not line:
        return None
    return line.decode("utf-8", errors="replace")


def _exit_ok() -> None:
    """Output empty JSON object and exit successfully."""
    sys.stdout.write("{}\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
