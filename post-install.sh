#!/bin/bash
set -e

# Claude Guardian - Post-Install Setup
# Installs hooks into ~/.claude/settings.json and copies default config.
# Works for both brew installs (/Applications/ClaudeGuardian.app) and local builds.

# Determine where we're running from
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect if running from inside .app bundle or from project root
if [[ "$SCRIPT_DIR" == *"Contents/Resources"* ]]; then
    # Running from inside .app bundle (brew install or manual .app launch)
    APP_RESOURCES="$SCRIPT_DIR"
    HOOK_DIR="$APP_RESOURCES/hook"
    DEFAULT_CONFIG="$APP_RESOURCES/guardian.config.json"
    BINARY_PATH="${SCRIPT_DIR%/Contents/Resources}/Contents/MacOS/ClaudeGuardian"
else
    # Running from project root (local dev)
    HOOK_DIR="$SCRIPT_DIR/hook"
    DEFAULT_CONFIG="$SCRIPT_DIR/guardian.config.json"
    # Check for .app build first, then raw binary
    if [ -f "$SCRIPT_DIR/build/ClaudeGuardian.app/Contents/MacOS/ClaudeGuardian" ]; then
        BINARY_PATH="$SCRIPT_DIR/build/ClaudeGuardian.app/Contents/MacOS/ClaudeGuardian"
        HOOK_DIR="$SCRIPT_DIR/build/ClaudeGuardian.app/Contents/Resources/hook"
        DEFAULT_CONFIG="$SCRIPT_DIR/build/ClaudeGuardian.app/Contents/Resources/guardian.config.json"
    elif [ -f "$SCRIPT_DIR/app/ClaudeGuardian/ClaudeGuardian" ]; then
        BINARY_PATH="$SCRIPT_DIR/app/ClaudeGuardian/ClaudeGuardian"
    else
        echo "Error: ClaudeGuardian binary not found. Run build-app.sh first."
        exit 1
    fi
fi

HOOK_SCRIPT="$HOOK_DIR/pre_tool_use.py"
LIFECYCLE_SCRIPT="$HOOK_DIR/session_lifecycle.py"
PERMISSION_SCRIPT="$HOOK_DIR/permission_request.py"
NOTIFICATION_SCRIPT="$HOOK_DIR/notification.py"
STOP_SCRIPT="$HOOK_DIR/stop.py"
SETTINGS_FILE="$HOME/.claude/settings.json"
USER_CONFIG_DIR="$HOME/.config/claude-guardian"
PLIST_NAME="com.claudeguardian.app"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "╔══════════════════════════════════════╗"
echo "║    Claude Guardian Post-Install      ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Step 1: Copy default config to user config dir
echo "[1/3] Setting up config..."
mkdir -p "$USER_CONFIG_DIR"
if [ ! -f "$USER_CONFIG_DIR/guardian.config.json" ]; then
    cp "$DEFAULT_CONFIG" "$USER_CONFIG_DIR/guardian.config.json"
    echo "  ✓ Config created at $USER_CONFIG_DIR/guardian.config.json"
else
    echo "  ✓ Config already exists (keeping your settings)"
fi

# Step 2: Install hooks into Claude Code settings
echo "[2/3] Installing Claude Code hooks..."
mkdir -p "$HOME/.claude"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

python3 -c "
import json

settings_path = '$SETTINGS_FILE'
hook_script = '$HOOK_SCRIPT'
lifecycle_script = '$LIFECYCLE_SCRIPT'
perm_script = '$PERMISSION_SCRIPT'
notif_script = '$NOTIFICATION_SCRIPT'
stop_script = '$STOP_SCRIPT'

with open(settings_path, 'r') as f:
    settings = json.load(f)

if 'hooks' not in settings:
    settings['hooks'] = {}

settings['hooks']['PreToolUse'] = [{
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{hook_script}'\",
        'timeout': 65
    }]
}]

settings['hooks']['SessionStart'] = [{
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{lifecycle_script}'\",
        'timeout': 5
    }]
}]

settings['hooks']['SessionEnd'] = [{
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{lifecycle_script}'\",
        'timeout': 5
    }]
}]

settings['hooks']['PermissionRequest'] = [{
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{perm_script}'\",
        'timeout': 305
    }]
}]

settings['hooks']['Notification'] = [{
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{notif_script}'\",
        'timeout': 5
    }]
}]

settings['hooks']['Stop'] = [{
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': f\"python3 '{stop_script}'\",
        'timeout': 12
    }]
}]

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print('  ✓ Hooks installed in', settings_path)
"

# Step 3: Set up launch agent
echo "[3/3] Setting up launch on login..."
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

# Launch the app
echo ""
echo "Launching Claude Guardian..."
pkill -f "ClaudeGuardian" 2>/dev/null || true
sleep 0.5

"$BINARY_PATH" &
disown
sleep 1

if curl -s --connect-timeout 2 "http://localhost:9001/health" | grep -q '"ok"'; then
    echo "  ✓ Guardian is running"
else
    echo "  ⚠ Guardian started but health check pending (may need a moment)"
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║         Setup Complete!              ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Config: $USER_CONFIG_DIR/guardian.config.json"
echo "  Logs:   /tmp/claude-guardian.log"
echo ""
