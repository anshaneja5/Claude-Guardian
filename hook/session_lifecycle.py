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
        last_match_comm = ""
        while cur and cur != 1:
            ppid = int(os.popen(f"ps -o ppid= -p {cur} 2>/dev/null").read().strip() or "1")
            comm = os.popen(f"ps -o comm= -p {ppid} 2>/dev/null").read().strip()
            name = os.path.basename(comm).lstrip("-")
            if name in known_terminals:
                last_match_pid = ppid
                last_match_name = name
                last_match_comm = comm
                # Keep going up — the top-most match is the activatable app
            cur = ppid
        terminal_pid = last_match_pid
        # For Electron-based apps, extract the real app name from the bundle path
        # e.g. "/Applications/Antigravity.app/Contents/MacOS/Electron" -> "Antigravity"
        if last_match_name == "Electron" and ".app/" in last_match_comm:
            app_path = last_match_comm.split(".app/")[0] + ".app"
            terminal_app = os.path.basename(app_path).replace(".app", "")
        else:
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
