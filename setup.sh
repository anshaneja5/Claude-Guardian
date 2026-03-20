#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/app/ClaudeGuardian"
HOOK_SCRIPT="$SCRIPT_DIR/hook/pre_tool_use.py"
LIFECYCLE_SCRIPT="$SCRIPT_DIR/hook/session_lifecycle.py"
PERMISSION_SCRIPT="$SCRIPT_DIR/hook/permission_request.py"
NOTIFICATION_SCRIPT="$SCRIPT_DIR/hook/notification.py"
SETTINGS_FILE="$HOME/.claude/settings.json"
BINARY_PATH="$APP_DIR/ClaudeGuardian"
PLIST_NAME="com.claudeguardian.app"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "╔══════════════════════════════════════╗"
echo "║       Claude Guardian Setup          ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Step 1: Build the Swift app
echo "[1/4] Building ClaudeGuardian app..."
cd "$APP_DIR"
swiftc -o ClaudeGuardian Sources/main.swift Sources/sprites.swift \
    -framework Cocoa \
    -framework SwiftUI \
    -framework Network \
    -O 2>&1
echo "  ✓ Built successfully"

# Step 2: Install the hook into Claude settings
echo "[2/4] Installing Claude Code hook..."
mkdir -p "$HOME/.claude"

# Create settings.json if it doesn't exist
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

# Use Python to safely merge hook config into existing settings
python3 -c "
import json, sys

settings_path = '$SETTINGS_FILE'
hook_script = '$HOOK_SCRIPT'

with open(settings_path, 'r') as f:
    settings = json.load(f)

# Build the hook entry
hook_entry = {
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{hook_script}'\",
        'timeout': 65
    }]
}

# Initialize hooks structure if needed
if 'hooks' not in settings:
    settings['hooks'] = {}

lifecycle_script = '$LIFECYCLE_SCRIPT'

lifecycle_entry = {
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{lifecycle_script}'\",
        'timeout': 5
    }]
}

settings['hooks']['PreToolUse'] = [hook_entry]
perm_script = '$PERMISSION_SCRIPT'

perm_entry = {
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{perm_script}'\",
        'timeout': 305
    }]
}

settings['hooks']['SessionStart'] = [lifecycle_entry]
settings['hooks']['SessionEnd'] = [lifecycle_entry]
notif_script = '$NOTIFICATION_SCRIPT'

notif_entry = {
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{notif_script}'\",
        'timeout': 5
    }]
}

settings['hooks']['PermissionRequest'] = [perm_entry]
settings['hooks']['Notification'] = [notif_entry]

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print('  ✓ Hook installed in', settings_path)
"

# Step 3: Set up launch-on-login
echo "[3/4] Setting up launch on login..."
cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/claude-guardian.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-guardian.err</string>
</dict>
</plist>
PLIST
echo "  ✓ Launch agent installed"

# Step 4: Launch the app
echo "[4/4] Launching Claude Guardian..."
# Kill existing instance if running
pkill -f "ClaudeGuardian" 2>/dev/null || true
sleep 0.5

"$BINARY_PATH" &
disown
sleep 1

# Verify it's running
if curl -s --connect-timeout 2 "http://localhost:9001/health" | grep -q '"ok"'; then
    echo "  ✓ Guardian is running on port 9001"
else
    echo "  ⚠ Guardian started but health check pending (may need a moment)"
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║         Setup Complete!              ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Look for the 🟢 icon in your menu bar."
echo ""
echo "  Config: $SCRIPT_DIR/guardian.config.json"
echo "  Logs:   /tmp/claude-guardian.log"
echo ""
echo "  To uninstall:"
echo "    launchctl unload $PLIST_PATH"
echo "    rm $PLIST_PATH"
echo "    Remove PreToolUse hook from $SETTINGS_FILE"
