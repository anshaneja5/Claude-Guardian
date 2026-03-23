#!/bin/bash
# Claude Guardian - Uninstall Script
# Removes hooks from ~/.claude/settings.json, stops the app, and cleans up.

SETTINGS_FILE="$HOME/.claude/settings.json"

echo "╔══════════════════════════════════════╗"
echo "║     Claude Guardian Uninstall        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Step 1: Stop the app
echo "[1/3] Stopping Claude Guardian..."
pkill -f ClaudeGuardian 2>/dev/null && echo "  ✓ App stopped" || echo "  ✓ App was not running"

# Step 2: Remove launch agent
echo "[2/3] Removing launch agent..."
PLIST_PATH="$HOME/Library/LaunchAgents/com.claudeguardian.app.plist"
if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null
    rm -f "$PLIST_PATH"
    echo "  ✓ Launch agent removed"
else
    echo "  ✓ No launch agent found"
fi

# Step 3: Remove hooks from Claude Code settings
echo "[3/3] Removing hooks from Claude Code settings..."
if [ -f "$SETTINGS_FILE" ]; then
    python3 -c "
import json, sys

settings_path = '$SETTINGS_FILE'

with open(settings_path, 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
changed = False

# Remove any hook that references claude-guardian or ClaudeGuardian
for hook_type in list(hooks.keys()):
    entries = hooks[hook_type]
    if isinstance(entries, list):
        filtered = []
        for entry in entries:
            hook_list = entry.get('hooks', [])
            has_guardian = any('guardian' in h.get('command', '').lower() or 'claudeguardian' in h.get('command', '').lower() for h in hook_list)
            if not has_guardian:
                filtered.append(entry)
            else:
                changed = True
        if filtered:
            hooks[hook_type] = filtered
        else:
            del hooks[hook_type]
            changed = True

if changed:
    if not hooks:
        del settings['hooks']
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
    print('  ✓ Guardian hooks removed from', settings_path)
else:
    print('  ✓ No Guardian hooks found in', settings_path)
"
else
    echo "  ✓ No Claude settings file found"
fi

echo ""
echo "  ✓ Uninstall complete!"
echo ""
echo "  Note: Config at ~/.config/claude-guardian/ was kept."
echo "  To remove it too: rm -rf ~/.config/claude-guardian"
echo ""
