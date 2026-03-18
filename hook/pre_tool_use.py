#!/usr/bin/env python3
"""
Claude Guardian - PreToolUse Hook Script
Intercepts Claude Code tool calls and forwards them to the Guardian overlay app
for user approval. Blocks until the user approves or denies.
"""

import sys
import json
import os
import urllib.request
import urllib.error
import time

GUARDIAN_PORT = 9001
GUARDIAN_URL = f"http://localhost:{GUARDIAN_PORT}"
CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "guardian.config.json")
POLL_INTERVAL = 0.5  # seconds between polls


def load_config():
    try:
        with open(CONFIG_PATH, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"auto_approve": [], "always_block": [], "timeout_seconds": 60}


def check_server():
    """Check if Guardian app is running."""
    try:
        req = urllib.request.Request(f"{GUARDIAN_URL}/health", method="GET")
        resp = urllib.request.urlopen(req, timeout=1)
        return resp.status == 200
    except Exception:
        return False


def send_cost_update(session_id, cost_usd):
    """Fire-and-forget cost update to Guardian."""
    if cost_usd <= 0:
        return
    try:
        payload = json.dumps({
            "event": "CostUpdate",
            "session_id": session_id,
            "cost_usd": cost_usd,
        }).encode("utf-8")
        req = urllib.request.Request(
            f"{GUARDIAN_URL}/session",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        urllib.request.urlopen(req, timeout=1)
    except Exception:
        pass


def send_permission_request(tool_name, tool_input, session_id):
    """Send a permission request to Guardian and wait for response."""
    payload = json.dumps({
        "tool_name": tool_name,
        "tool_input": tool_input,
        "session_id": session_id,
        "timestamp": time.time()
    }).encode("utf-8")

    req = urllib.request.Request(
        f"{GUARDIAN_URL}/request",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    try:
        resp = urllib.request.urlopen(req, timeout=2)
        data = json.loads(resp.read().decode("utf-8"))
        request_id = data.get("request_id")
        if not request_id:
            return None
        return request_id
    except Exception:
        return None


def poll_for_decision(request_id, timeout=60):
    """Poll Guardian for the user's decision. Blocks until response or timeout."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            req = urllib.request.Request(
                f"{GUARDIAN_URL}/decision/{request_id}",
                method="GET"
            )
            resp = urllib.request.urlopen(req, timeout=5)
            data = json.loads(resp.read().decode("utf-8"))

            status = data.get("status")
            if status == "pending":
                time.sleep(POLL_INTERVAL)
                continue
            elif status == "approved":
                return "allow", data.get("message", "")
            elif status == "denied":
                return "deny", data.get("message", "User denied this action")
            elif status == "timeout":
                return "deny", "Request timed out - auto-denied"
            else:
                time.sleep(POLL_INTERVAL)
                continue
        except urllib.error.URLError:
            # Server went away
            return None, "Guardian app not responding"
        except Exception:
            time.sleep(POLL_INTERVAL)
            continue

    return "deny", "Hook polling timed out"


def main():
    raw_input = sys.stdin.read()
    try:
        hook_input = json.loads(raw_input)
    except json.JSONDecodeError:
        sys.exit(0)

    tool_name = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})
    session_id = hook_input.get("session_id", "unknown")

    # Send cost update if available
    cost_data = hook_input.get("cost", {})
    cost_usd = cost_data.get("total_cost_usd", 0) if isinstance(cost_data, dict) else 0
    if cost_usd > 0:
        send_cost_update(session_id, cost_usd)

    config = load_config()

    # Check auto-approve list
    if tool_name in config.get("auto_approve", []):
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": f"Auto-approved: {tool_name} is in auto_approve list"
            }
        }
        print(json.dumps(result))
        sys.exit(0)

    # Check always-block list
    if tool_name in config.get("always_block", []):
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"Blocked: {tool_name} is in always_block list"
            }
        }
        print(json.dumps(result))
        sys.exit(0)

    # Check if Guardian is running
    if not check_server():
        # Fall back to allowing (Claude Code's own permission system handles it)
        sys.exit(0)

    # Send request to Guardian overlay
    request_id = send_permission_request(tool_name, tool_input, session_id)
    if not request_id:
        # Failed to send, fall through to Claude Code's default
        sys.exit(0)

    # Block and wait for user decision
    timeout = config.get("timeout_seconds", 60)
    decision, message = poll_for_decision(request_id, timeout)

    if decision == "allow":
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": "Approved via Claude Guardian"
            }
        }
        print(json.dumps(result))
        sys.exit(0)
    elif decision == "deny":
        reason = message if message else "Denied via Claude Guardian"
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason
            }
        }
        print(json.dumps(result))
        sys.exit(0)
    else:
        # Something went wrong, fall through
        sys.exit(0)


if __name__ == "__main__":
    main()
