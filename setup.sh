#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════╗"
echo "║       Claude Guardian Setup          ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Step 1: Build the .app bundle
echo "[1/2] Building ClaudeGuardian.app..."
"$SCRIPT_DIR/build-app.sh"

# Step 2: Run post-install (hooks, config, launch agent, start app)
echo "[2/2] Running post-install setup..."
"$SCRIPT_DIR/post-install.sh"
