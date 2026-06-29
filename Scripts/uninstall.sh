#!/bin/bash
set -euo pipefail

echo "==> Agent Beacon Uninstaller"
echo ""
echo "This will remove:"
echo "  - /Applications/AgentBeacon.app"
echo "  - /usr/local/bin/agent-beacon"
echo "  - /usr/local/bin/agent-codex"
echo "  - /usr/local/bin/agent-beacon-claude-notify"
echo "  - ~/Library/LaunchAgents/com.agentbeacon.app.plist"
echo ""
echo "This will NOT touch:"
echo "  - ~/.agent-beacon/status/  (your status data)"
echo "  - ~/.claude/settings.json  (Claude Code config)"
echo "  - ~/.codex/config.toml     (Codex config)"
echo ""
read -p "Continue? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.agentbeacon.app.plist"

# Stop app
echo "--> Stopping Agent Beacon..."
if [ -f "$LAUNCH_AGENT" ]; then
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
fi
killall AgentBeaconApp 2>/dev/null || true

# Remove files
echo "--> Removing app bundle..."
rm -rf /Applications/AgentBeacon.app 2>/dev/null || true

echo "--> Removing CLI tools..."
rm -f /usr/local/bin/agent-beacon
rm -f /usr/local/bin/agent-codex
rm -f /usr/local/bin/agent-beacon-claude-notify

echo "--> Removing LaunchAgent..."
rm -f "$LAUNCH_AGENT"

echo ""
echo "==> Done. Agent Beacon removed."
echo ""
echo "To restore Claude Code hooks, your original settings.json backup is at:"
echo "  ~/.claude/settings.json.agent-beacon-backup-*"
echo ""
echo "To remove status data: rm -rf ~/.agent-beacon/"
echo "To undo Codex hooks: see README.md § Uninstall"
