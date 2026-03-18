# Claude Guardian

A native macOS overlay app that acts as a permission manager for Claude Code CLI sessions. When Claude wants to run a shell command, write a file, or perform any action — a floating widget appears on your screen with the details, so you can approve or deny without switching to your terminal.

## How It Works

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant Hook as pre_tool_use.py
    participant Config as guardian.config.json
    participant Server as Guardian HTTP Server
    participant UI as Mascot Widget

    CC->>Hook: PreToolUse event (stdin JSON)
    Hook->>Config: Check auto_approve / always_block

    alt Tool is auto-approved
        Hook-->>CC: permissionDecision: "allow"
    else Tool is always blocked
        Hook-->>CC: permissionDecision: "deny"
    else Tool needs user approval
        Hook->>Server: POST /request (tool details)
        Server->>UI: Show permission panel
        UI->>UI: User sees tool name + content

        alt User clicks Allow
            UI->>Server: Decision: approved
        else User clicks Deny
            UI->>Server: Decision: denied + message
        else Timeout
            UI->>Server: Decision: timeout (auto-deny)
        end

        loop Poll until decision
            Hook->>Server: GET /decision/{id}
            Server-->>Hook: status: pending / approved / denied
        end

        Hook-->>CC: permissionDecision + reason
    end
```

1. Claude Code triggers a **PreToolUse hook** before every tool call
2. The hook script (`pre_tool_use.py`) checks the config — auto-approves safe tools (Read, Glob, etc.), auto-blocks banned tools, and forwards everything else to the Guardian app via HTTP
3. The Guardian app shows a **permission panel** attached to a pixel art mascot widget on your screen
4. You click **Allow** or **Deny** (with an optional message back to Claude)
5. The hook receives your decision and tells Claude Code to proceed or stop

## Quick Start

```bash
./setup.sh
```

This will:
1. Compile the Swift app using your system's Swift toolchain
2. Install the PreToolUse hook into `~/.claude/settings.json`
3. Create a LaunchAgent so Guardian starts on login
4. Launch the app immediately

### Manual Start

If you prefer to run it manually:

```bash
# Build
cd app/ClaudeGuardian
swiftc -o ClaudeGuardian Sources/main.swift Sources/sprites.swift \
    -framework Cocoa -framework SwiftUI -framework Network

# Run
./ClaudeGuardian &
```

## Features

### Mascot Widget
- An animated pixel art mascot lives in the bottom-right corner of your screen
- Always-on-top, draggable to any position
- Shows current status: **IDLE**, **WORKING**, **NEEDS YOU**, **APPROVED!**, **DENIED**
- Animations change based on state:
  - **Idle**: breathing + blinking cycle
  - **Permission pending**: waving / ear wiggle
  - **Approved**: happy expression (^_^)
  - **Denied**: sad expression with droopy ears

### Permission Panel
- Expands below the mascot when Claude needs approval
- Shows the **tool type** (Shell Command, Write File, Edit File, etc.)
- Shows the **exact content** — the command, file path, code changes, etc.
- **Allow** button (or press **Enter**) to approve
- **Deny** button (or press **Esc**) to reject
  - Click Deny once to reveal a text field where you can type a message back to Claude (e.g. "don't delete that, use X instead")
  - Click "Send & Deny" to send the message and reject
- Countdown timer — auto-denies after timeout (default 300 seconds)
- Panel collapses back to just the mascot after you respond

### Menu Bar
- Status icon in the macOS menu bar: 🟢 idle, 🟠 active, 🔴 needs attention, ✅ just approved, ❌ just denied
- Click the icon to see:
  - Approve/deny stats
  - Searchable action history log (last 50 actions)
  - Filter bar to search by tool name or content
  - Quit button

### Fallback Behavior
- If the Guardian app isn't running, the hook exits silently and Claude Code falls back to its own built-in permission prompts
- No action is ever silently approved — if something goes wrong, it fails safe

## Configuration

Edit `guardian.config.json`:

```json
{
  "port": 9001,
  "timeout_seconds": 300,
  "mascot": "cat",
  "auto_approve": ["Read", "Glob", "Grep", "LS"],
  "always_block": [],
  "ask": ["Bash", "Write", "Edit", "NotebookEdit"]
}
```

| Field | Description |
|-------|-------------|
| `port` | HTTP port for hook ↔ app communication (default `9001`) |
| `timeout_seconds` | Auto-deny after this many seconds of no response (default `300`) |
| `mascot` | Which pixel art mascot to display (see below) |
| `auto_approve` | Tool names that pass through without asking |
| `always_block` | Tool names that are always denied |
| `ask` | Tool names that show the permission overlay (everything not in the above two lists also defaults to asking) |

### Mascots

Set `"mascot"` to any of these values. Here's what each one looks like:

| `"claude"` | `"cat"` | `"owl"` | `"skull"` | `"dog"` | `"dragon"` |
|:-:|:-:|:-:|:-:|:-:|:-:|
| <img src="assets/claude.png" width="64"> | <img src="assets/cat.png" width="64"> | <img src="assets/owl.png" width="64"> | <img src="assets/skull.png" width="64"> | <img src="assets/dog.png" width="64"> | <img src="assets/dragon.png" width="64"> |
| Coral Claude | Dark Gray Cat | Brown Owl | Pixel Skull | Golden Puppy | Green Dragon |

Change the mascot anytime — just edit the config and restart the app.

## Architecture

### Hook Script (`hook/pre_tool_use.py`)
- Receives JSON on stdin from Claude Code's PreToolUse hook event
- Reads `guardian.config.json` to check auto-approve/block lists
- For tools that need approval: POSTs to `localhost:9001/request`, then polls `localhost:9001/decision/{id}` until the user responds
- Returns JSON to Claude Code with `permissionDecision: "allow"` or `"deny"` and an optional reason

### Swift App (`app/ClaudeGuardian/Sources/`)
- **`main.swift`**: App delegate, HTTP server (NWListener), window management, SwiftUI views for the unified widget, history popover, and menu bar
- **`sprites.swift`**: All pixel art mascot sprites (16x16 grids) with animation frames and color palettes
- Runs as a menubar-only app (no Dock icon)
- HTTP server on the configured port handles `/health`, `/request`, and `/decision/{id}` endpoints
- The overlay window uses `.screenSaver` level to appear above fullscreen apps

## File Structure

```
claude-guardian/
├── setup.sh                              # One-command install + build + launch
├── guardian.config.json                   # Runtime config (port, timeout, mascot, rules)
├── hook/
│   └── pre_tool_use.py                   # Claude Code PreToolUse hook script
├── app/
│   └── ClaudeGuardian/
│       └── Sources/
│           ├── main.swift                # App, HTTP server, UI views
│           └── sprites.swift             # Pixel art mascot sprite data
├── assets/                               # Generated mascot preview images
│   ├── claude.png
│   ├── cat.png
│   ├── owl.png
│   ├── skull.png
│   ├── dog.png
│   └── dragon.png
├── generate_pngs.py                      # Script to regenerate mascot PNGs from sprites
└── README.md
```

## Requirements

- macOS 13+ (Ventura or later)
- Swift 5.9+ (included with Xcode or Xcode Command Line Tools)
- Python 3 (pre-installed on macOS)
- Claude Code CLI with hooks support

## Uninstall

```bash
# 1. Stop the running app
pkill -f ClaudeGuardian

# 2. Remove the launch agent
launchctl unload ~/Library/LaunchAgents/com.claudeguardian.app.plist
rm ~/Library/LaunchAgents/com.claudeguardian.app.plist

# 3. Remove the hook from Claude Code settings
# Edit ~/.claude/settings.json and delete the PreToolUse entry

# 4. Delete the project folder
rm -rf /path/to/claude-guardian
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Enter` / `Return` | Allow the pending action |
| `Escape` | Deny (first press reveals message field, second press sends) |

## Troubleshooting

**Hook error about spaces in path**: If your project folder path contains spaces, make sure the hook command in `~/.claude/settings.json` wraps the script path in single quotes:
```json
"command": "python3 '/path/with spaces/hook/pre_tool_use.py'"
```

**Overlay doesn't appear**: Check that the Guardian app is running (`curl http://localhost:9001/health` should return `{"status":"ok"}`). If not, launch it manually.

**Port conflict**: If port 9001 is taken, change `"port"` in both `guardian.config.json` and the hook script's `GUARDIAN_PORT` variable.
