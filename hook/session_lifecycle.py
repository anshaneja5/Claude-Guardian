#!/usr/bin/env python3
"""
Claude Guardian - Session Lifecycle Hook
Notifies the Guardian app when sessions start/end so it can spawn/remove mascots.
Used for SessionStart and SessionEnd hooks. Fire-and-forget (non-blocking).
"""

import sys
import json
import urllib.request

GUARDIAN_PORT = 9001
GUARDIAN_URL = f"http://localhost:{GUARDIAN_PORT}"


def notify(event, session_id, cwd=""):
    payload = json.dumps({
        "event": event,
        "session_id": session_id,
        "cwd": cwd,
    }).encode("utf-8")

    req = urllib.request.Request(
        f"{GUARDIAN_URL}/session",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        urllib.request.urlopen(req, timeout=2)
    except Exception:
        pass  # Guardian not running, ignore


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        sys.exit(0)

    event = data.get("hook_event_name", "")
    session_id = data.get("session_id", "unknown")
    cwd = data.get("cwd", "")

    if event in ("SessionStart", "SessionEnd"):
        notify(event, session_id, cwd)

    sys.exit(0)


if __name__ == "__main__":
    main()
