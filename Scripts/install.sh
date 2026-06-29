#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/AgentBeacon.app"
CLI_BINARY="$PROJECT_DIR/agent-beacon"
CODEX_WRAPPER="$PROJECT_DIR/Wrappers/agent-codex"
CLAUDE_NOTIFY="$PROJECT_DIR/Wrappers/agent-beacon-claude-notify"

echo "==> Agent Beacon Installer"
echo ""

# Verify build exists
if [ ! -f "$APP_BUNDLE/Contents/MacOS/AgentBeaconApp" ]; then
    echo "ERROR: App not built. Run ./Scripts/build.sh first."
    exit 1
fi
if [ ! -f "$CLI_BINARY" ]; then
    echo "ERROR: CLI not built. Run ./Scripts/build.sh first."
    exit 1
fi

# --- Install App Bundle ---
echo "--> Installing app to /Applications/AgentBeacon.app"
if [ -d "/Applications/AgentBeacon.app" ]; then
    echo "    Removing previous installation..."
    rm -rf "/Applications/AgentBeacon.app"
fi
cp -r "$APP_BUNDLE" "/Applications/"
xattr -cr "/Applications/AgentBeacon.app" 2>/dev/null || true
echo "    Done."

# --- Install CLI ---
echo "--> Installing agent-beacon CLI to /usr/local/bin/"
mkdir -p /usr/local/bin
cp "$CLI_BINARY" /usr/local/bin/agent-beacon
chmod +x /usr/local/bin/agent-beacon
echo "    Done."

# --- Install Codex wrapper ---
echo "--> Installing agent-codex wrapper to /usr/local/bin/"
cp "$CODEX_WRAPPER" /usr/local/bin/agent-codex
chmod +x /usr/local/bin/agent-codex
echo "    Done."

# --- Install Claude notify hook ---
echo "--> Installing agent-beacon-claude-notify to /usr/local/bin/"
cp "$CLAUDE_NOTIFY" /usr/local/bin/agent-beacon-claude-notify
chmod +x /usr/local/bin/agent-beacon-claude-notify
echo "    Done."

# --- Create status directory ---
echo "--> Creating status directory ~/.agent-beacon/status/"
mkdir -p ~/.agent-beacon/status
echo "    Done."

# --- LaunchAgent for auto-start ---
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="$LAUNCH_AGENT_DIR/com.agentbeacon.app.plist"
echo "--> Installing LaunchAgent for auto-start at login..."
mkdir -p "$LAUNCH_AGENT_DIR"
cp "$PROJECT_DIR/Resources/com.agentbeacon.app.plist" "$LAUNCH_AGENT_PLIST"
launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT_PLIST"
echo "    Done."

echo ""
echo "==> Installation complete!"
echo ""
echo "  App:        /Applications/AgentBeacon.app"
echo "  CLI:        /usr/local/bin/agent-beacon"
echo "  Codex wrap: /usr/local/bin/agent-codex"
echo "  Status dir: ~/.agent-beacon/status/"
echo "  LaunchAgent: $LAUNCH_AGENT_PLIST"
echo ""
echo "The app should now appear in your menu bar."
echo "Run: ./Scripts/setup-hooks.sh  to configure Claude Code and Codex hooks."
echo ""
echo "  Quick test:"
echo "    agent-beacon set claude running '测试运行中'"
echo "    agent-beacon list"
echo "    agent-beacon reset all"
