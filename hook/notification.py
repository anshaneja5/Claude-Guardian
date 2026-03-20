#!/usr/bin/env python3
"""
Claude Guardian - Notification Hook
Forwards Claude Code notifications to the Guardian mascot as speech bubbles.
"""

import sys
import json
import urllib.request

GUARDIAN_PORT = 9001
GUARDIAN_URL = f"http://localhost:{GUARDIAN_PORT}"


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        sys.exit(0)

    session_id = data.get("session_id", "unknown")
    # Notification message can be in different fields
    message = data.get("message", "") or data.get("notification", "") or data.get("content", "")

    if not message:
        sys.exit(0)

    # Send to Guardian
    try:
        payload = json.dumps({
            "event": "Notification",
            "session_id": session_id,
            "message": message[:200],  # truncate long messages
        }).encode("utf-8")

        req = urllib.request.Request(
            f"{GUARDIAN_URL}/session",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        urllib.request.urlopen(req, timeout=2)
    except Exception:
        pass

    sys.exit(0)


if __name__ == "__main__":
    main()
