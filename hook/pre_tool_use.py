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

POLL_INTERVAL = 0.5  # seconds between polls


def _find_config_path():
    """Find guardian.config.json: user override > bundled default."""
    user_config = os.path.expanduser("~/.config/claude-guardian/guardian.config.json")
    if os.path.isfile(user_config):
        return user_config
    # Bundled: script is in hook/ dir, config is sibling to hook/
    bundled = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "guardian.config.json")
    if os.path.isfile(bundled):
        return bundled
    return None


def load_config():
    config_path = _find_config_path()
    if not config_path:
        return {"auto_approve": [], "always_block": [], "timeout_seconds": 60}
    try:
        with open(config_path, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"auto_approve": [], "always_block": [], "timeout_seconds": 60}


def _get_guardian_url():
    config = load_config()
    port = config.get("port", 9001)
    return f"http://localhost:{port}"


GUARDIAN_URL = _get_guardian_url()


def is_claude_allowed(tool_name, tool_input):
    """Check if this tool call is already allowed in Claude Code's settings allow lists.
    If so, Guardian should not intercept — let Claude Code handle it silently."""
    settings_paths = [
        os.path.expanduser("~/.claude/settings.json"),
        os.path.expanduser("~/.claude/settings.local.json"),
        os.path.join(os.getcwd(), ".claude", "settings.json"),
        os.path.join(os.getcwd(), ".claude", "settings.local.json"),
    ]
    allow_patterns = []
    for path in settings_paths:
        try:
            with open(path, "r") as f:
                data = json.load(f)
            allow_patterns.extend(data.get("permissions", {}).get("allow", []))
        except Exception:
            pass

    if not allow_patterns:
        return False

    # Get the primary string argument for the tool (e.g. command for Bash, file_path for Write)
    tool_arg = ""
    if isinstance(tool_input, dict):
        tool_arg = (tool_input.get("command") or tool_input.get("file_path") or
                    tool_input.get("path") or tool_input.get("query") or "")

    for pattern in allow_patterns:
        # Pattern format: "ToolName(arg_pattern)" or just "ToolName"
        if "(" in pattern:
            pat_tool = pattern[:pattern.index("(")]
            pat_arg = pattern[pattern.index("(")+1:pattern.rindex(")")]
        else:
            pat_tool = pattern
            pat_arg = "*"

        if pat_tool != tool_name:
            continue

        # Match arg pattern: supports * wildcard and prefix matching like "chmod:*"
        if pat_arg == "*":
            return True
        if "*" in pat_arg:
            prefix = pat_arg.split("*")[0]
            if tool_arg.startswith(prefix):
                return True
        elif tool_arg == pat_arg:
            return True

    return False


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


def is_bypass_mode(config):
    """Detect if Claude Code is running with bypass permissions (--dangerously-skip-permissions).
    Also returns True if notify_only is set in guardian config."""
    if config.get("notify_only", False):
        return True
    try:
        cur = os.getpid()
        while cur and cur != 1:
            ppid = int(os.popen(f"ps -o ppid= -p {cur} 2>/dev/null").read().strip() or "1")
            args = os.popen(f"ps -o args= -p {ppid} 2>/dev/null").read().strip()
            if "dangerously-skip-permissions" in args:
                return True
            cur = ppid
    except Exception:
        pass
    return False


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

    # If already allowed in Claude Code's own settings, don't intercept — fall through silently
    if is_claude_allowed(tool_name, tool_input):
        sys.exit(0)

    # In bypass/notify-only mode: do nothing at all — silent passthrough
    if is_bypass_mode(config):
        sys.exit(0)

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
