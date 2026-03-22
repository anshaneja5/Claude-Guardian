#!/usr/bin/env python3
"""
Claude Guardian - Notification Hook
Forwards Claude Code notifications to the Guardian mascot as speech bubbles.
"""

import sys
import json
import urllib.request

import os


def _find_config_path():
    user_config = os.path.expanduser("~/.config/claude-guardian/guardian.config.json")
    if os.path.isfile(user_config):
        return user_config
    bundled = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "guardian.config.json")
    if os.path.isfile(bundled):
        return bundled
    return None


def _get_guardian_url():
    config_path = _find_config_path()
    port = 9001
    if config_path:
        try:
            with open(config_path, "r") as f:
                port = json.load(f).get("port", 9001)
        except Exception:
            pass
    return f"http://localhost:{port}"


GUARDIAN_URL = _get_guardian_url()


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
