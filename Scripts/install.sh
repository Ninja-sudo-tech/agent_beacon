#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/AgentBeacon.app"
CLI_BINARY="$PROJECT_DIR/agent-beacon"
CODEX_WRAPPER="$PROJECT_DIR/Wrappers/agent-codex"
CLAUDE_NOTIFY="$PROJECT_DIR/Wrappers/agent-beacon-claude-notify"
GEMINI_WATCHER="$PROJECT_DIR/Wrappers/agent-gemini-watcher"
CLAUDE_WATCHER="$PROJECT_DIR/Wrappers/agent-claude-watcher"
CODEX_WATCHER="$PROJECT_DIR/Wrappers/agent-codex-watcher"
BIN_DIR="$HOME/.local/bin"

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

# --- Install CLI + wrappers + watchers to ~/.local/bin (no sudo needed) ---
echo "--> Installing CLI and watcher daemons to $BIN_DIR/"
mkdir -p "$BIN_DIR"
cp "$CLI_BINARY"      "$BIN_DIR/agent-beacon"
cp "$CODEX_WRAPPER"   "$BIN_DIR/agent-codex"
cp "$CLAUDE_NOTIFY"   "$BIN_DIR/agent-beacon-claude-notify"
cp "$GEMINI_WATCHER"  "$BIN_DIR/agent-gemini-watcher"
cp "$CLAUDE_WATCHER"  "$BIN_DIR/agent-claude-watcher"
cp "$CODEX_WATCHER"   "$BIN_DIR/agent-codex-watcher"
chmod +x "$BIN_DIR/agent-beacon" "$BIN_DIR/agent-codex" "$BIN_DIR/agent-beacon-claude-notify" \
         "$BIN_DIR/agent-gemini-watcher" "$BIN_DIR/agent-claude-watcher" "$BIN_DIR/agent-codex-watcher"
echo "    Done."
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "    NOTE: $BIN_DIR is not on your PATH. Add to your shell profile:"
    echo "          export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# --- Create status directory ---
echo "--> Creating status directory ~/.agent-beacon/status/"
mkdir -p ~/.agent-beacon/status
echo "    Done."

# --- LaunchAgents for auto-start (App + 3 watcher daemons) ---
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENT_DIR"
echo "--> Installing LaunchAgents for auto-start at login..."

install_agent() {
    local plist_name="$1"
    local plist_path="$LAUNCH_AGENT_DIR/$plist_name"
    cp "$PROJECT_DIR/Resources/$plist_name" "$plist_path"
    launchctl unload "$plist_path" 2>/dev/null || true
    launchctl load "$plist_path"
    echo "    $plist_name"
}

install_agent "com.agentbeacon.app.plist"
install_agent "com.agentbeacon.gemini-watcher.plist"
install_agent "com.agentbeacon.claude-watcher.plist"
install_agent "com.agentbeacon.codex-watcher.plist"
echo "    Done."

echo ""
echo "==> Installation complete!"
echo ""
echo "  App:         /Applications/AgentBeacon.app"
echo "  CLI:         $BIN_DIR/agent-beacon"
echo "  Codex wrap:  $BIN_DIR/agent-codex"
echo "  Watchers:    $BIN_DIR/agent-{gemini,claude,codex}-watcher (4 LaunchAgents running)"
echo "  Status dir:  ~/.agent-beacon/status/"
echo ""
echo "The app should now appear in your menu bar."
echo "Run: ./Scripts/setup-hooks.sh  to configure Claude Code and Codex hooks."
echo ""
echo "  Quick test:"
echo "    agent-beacon set claude running '测试运行中'"
echo "    agent-beacon list"
echo "    agent-beacon reset all"
