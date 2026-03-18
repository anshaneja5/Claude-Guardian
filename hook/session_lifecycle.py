#!/usr/bin/env python3
"""
Claude Guardian - Session Lifecycle Hook
Notifies the Guardian app when sessions start/end so it can spawn/remove mascots.
Also sends terminal PID so Guardian can focus the right terminal window.
"""

import sys
import json
import os
import urllib.request

GUARDIAN_PORT = 9001
GUARDIAN_URL = f"http://localhost:{GUARDIAN_PORT}"


def find_terminal_info():
    """Walk up process tree to find the terminal app PID and name."""
    terminal_pid = 0
    terminal_app = ""
    known_terminals = {
        "Terminal", "iTerm2", "wezterm-gui", "kitty", "Cursor", "Code",
        "Windsurf", "ghostty", "alacritty", "Warp", "Zed",
        "Antigravity Helper", "Antigravity", "Electron",
        "Hyper", "Tabby", "Rio", "WarpTerminal",
    }
    try:
        cur = os.getpid()
        last_match_pid = 0
        last_match_name = ""
        while cur and cur != 1:
            ppid = int(os.popen(f"ps -o ppid= -p {cur} 2>/dev/null").read().strip() or "1")
            comm = os.popen(f"ps -o comm= -p {ppid} 2>/dev/null").read().strip()
            name = os.path.basename(comm).lstrip("-")
            if name in known_terminals:
                last_match_pid = ppid
                last_match_name = name
                # Keep going up — the top-most match is the activatable app
            cur = ppid
        terminal_pid = last_match_pid
        terminal_app = last_match_name
    except Exception:
        pass
    return terminal_pid, terminal_app


def notify(event, session_id, cwd="", terminal_pid=0, terminal_app=""):
    payload = json.dumps({
        "event": event,
        "session_id": session_id,
        "cwd": cwd,
        "terminal_pid": terminal_pid,
        "terminal_app": terminal_app,
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
        pass


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        sys.exit(0)

    event = data.get("hook_event_name", "")
    session_id = data.get("session_id", "unknown")
    cwd = data.get("cwd", "")

    if event == "SessionStart":
        terminal_pid, terminal_app = find_terminal_info()
        notify(event, session_id, cwd, terminal_pid, terminal_app)
    elif event == "SessionEnd":
        notify(event, session_id)

    sys.exit(0)


if __name__ == "__main__":
    main()
