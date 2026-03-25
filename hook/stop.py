#!/usr/bin/env python3
"""
Claude Guardian - Stop Hook
Fires when Claude finishes a response. Shows a notification on the mascot.
If the mascot app is not running, launches it first, then notifies.
Falls back to a macOS system notification only if the app fails to start.
"""

import sys
import json
import os
import time
import urllib.request
import subprocess


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


def guardian_running(url):
    try:
        req = urllib.request.Request(f"{url}/health", method="GET")
        resp = urllib.request.urlopen(req, timeout=1)
        return resp.status == 200
    except Exception:
        return False


def launch_guardian():
    """Launch the ClaudeGuardian app and wait up to 5 seconds for it to start."""
    try:
        subprocess.Popen(
            ["open", "-a", "ClaudeGuardian"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def notify_guardian(url, session_id, message):
    try:
        payload = json.dumps({
            "event": "Notification",
            "session_id": session_id,
            "message": message,
        }).encode("utf-8")
        req = urllib.request.Request(
            f"{url}/session",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        urllib.request.urlopen(req, timeout=2)
    except Exception:
        pass


def system_notification(title, message):
    """Show a macOS system notification as last-resort fallback."""
    try:
        script = f'display notification "{message}" with title "{title}"'
        subprocess.run(["osascript", "-e", script], timeout=3, capture_output=True)
    except Exception:
        pass


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        sys.exit(0)

    session_id = data.get("session_id", "unknown")
    url = _get_guardian_url()

    if not guardian_running(url):
        launch_guardian()
        # Wait up to 5 seconds for the app to start
        for _ in range(10):
            time.sleep(0.5)
            if guardian_running(url):
                break

    if guardian_running(url):
        # App is running — notify it. If there's no active session (bypass mode),
        # the app will create a temporary mascot to show the notification.
        notify_guardian(url, session_id, "Claude finished coding! ✓")
    else:
        # App failed to start — fall back to system notification
        system_notification("Claude Guardian", "Claude finished coding!")

    sys.exit(0)


if __name__ == "__main__":
    main()
