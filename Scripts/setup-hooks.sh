#!/bin/bash
set -euo pipefail

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_CONFIG="$HOME/.codex/config.toml"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "==> Agent Beacon Hook Setup"
echo ""

# ──────────────────────────────────────────────
# Claude Code hooks
# ──────────────────────────────────────────────

echo "--- Claude Code ($(claude --version 2>/dev/null || echo 'not found')) ---"

if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo "    No settings.json found, skipping Claude Code hooks."
else
    BACKUP="$CLAUDE_SETTINGS.agent-beacon-backup-$TIMESTAMP"
    cp "$CLAUDE_SETTINGS" "$BACKUP"
    echo "    Backup created: $BACKUP"

    # Use Python to safely merge hooks into existing settings.json
    python3 << PYEOF
import json, sys

path = "$CLAUDE_SETTINGS"
beacon_cli = "/usr/local/bin/agent-beacon"
notify_hook = "/usr/local/bin/agent-beacon-claude-notify"

with open(path) as f:
    settings = json.load(f)

if "hooks" not in settings:
    settings["hooks"] = {}

# --- UserPromptSubmit → running ---
if "UserPromptSubmit" not in settings["hooks"]:
    settings["hooks"]["UserPromptSubmit"] = []

existing_ups = settings["hooks"]["UserPromptSubmit"]
beacon_hook_ups = {
    "hooks": [{
        "type": "command",
        "command": f"{beacon_cli} set claude running '处理中' 2>/dev/null; cat > /dev/null"
    }]
}
if not any("agent-beacon" in str(h) for h in existing_ups):
    existing_ups.append(beacon_hook_ups)
    print("    Added UserPromptSubmit hook")
else:
    print("    UserPromptSubmit hook already present, skipped")

# --- Stop → done ---
if "Stop" not in settings["hooks"]:
    settings["hooks"]["Stop"] = []

existing_stop = settings["hooks"]["Stop"]
beacon_hook_stop = {
    "hooks": [{
        "type": "command",
        "command": f"{beacon_cli} set claude done '已完成' 2>/dev/null; cat > /dev/null"
    }]
}
if not any("agent-beacon" in str(h) for h in existing_stop):
    existing_stop.append(beacon_hook_stop)
    print("    Added Stop hook")
else:
    print("    Stop hook already present, skipped")

# --- Notification → waiting (permission check) ---
if "Notification" not in settings["hooks"]:
    settings["hooks"]["Notification"] = []

existing_notif = settings["hooks"]["Notification"]
beacon_hook_notif = {
    "hooks": [{
        "type": "command",
        "command": f"{notify_hook}"
    }]
}
if not any("agent-beacon" in str(h) for h in existing_notif):
    existing_notif.append(beacon_hook_notif)
    print("    Added Notification hook")
else:
    print("    Notification hook already present, skipped")

with open(path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("    Claude Code settings.json updated.")
PYEOF

fi

echo ""

# ──────────────────────────────────────────────
# Codex hooks (notify field in config.toml)
# ──────────────────────────────────────────────

echo "--- Codex ($(codex --version 2>/dev/null || echo 'not found')) ---"

if [ ! -f "$CODEX_CONFIG" ]; then
    echo "    No config.toml found, skipping Codex notify hook."
else
    BACKUP_CODEX="$CODEX_CONFIG.agent-beacon-backup-$TIMESTAMP"
    cp "$CODEX_CONFIG" "$BACKUP_CODEX"
    echo "    Backup created: $BACKUP_CODEX"

    # Check if notify is already pointing to our wrapper
    if grep -q "agent-beacon-codex-notify" "$CODEX_CONFIG" 2>/dev/null; then
        echo "    Codex notify hook already configured, skipped."
    else
        # Get current notify value and build wrapper script
        CURRENT_NOTIFY=$(grep '^notify' "$CODEX_CONFIG" | head -1 || echo "")
        WRAPPER_SCRIPT="/usr/local/bin/agent-beacon-codex-notify"

        if [ -n "$CURRENT_NOTIFY" ]; then
            # Extract the current notify array to preserve it
            EXISTING_CMD=$(python3 -c "
import re, sys
line = '''$CURRENT_NOTIFY'''
m = re.search(r'notify\s*=\s*(\[.*\])', line)
if m:
    print(m.group(1))
" 2>/dev/null || echo "")
            echo "    Current notify: $CURRENT_NOTIFY"
        fi

        # Write the codex notify wrapper
        cat > "$WRAPPER_SCRIPT" << 'WRAPEOF'
#!/bin/bash
# Agent Beacon — Codex turn-ended notify wrapper
# Called by Codex when a turn ends. First arg may be "turn-ended" or event type.
EVENT="${1:-turn-ended}"
BEACON="/usr/local/bin/agent-beacon"

# Notify Agent Beacon
case "$EVENT" in
    turn-ended|done|complete)
        "$BEACON" set codex done "Turn ended" 2>/dev/null &
        ;;
    error|failed)
        "$BEACON" set codex error "Codex error" 2>/dev/null &
        ;;
    *)
        "$BEACON" set codex done "Notified: $EVENT" 2>/dev/null &
        ;;
esac

# Call original Codex Computer Use notify if it exists
ORIGINAL="/Users/loutengda/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
if [ -f "$ORIGINAL" ]; then
    "$ORIGINAL" "$@" 2>/dev/null &
fi
WRAPEOF
        chmod +x "$WRAPPER_SCRIPT"

        # Update config.toml notify field
        python3 << PYEOF2
import re

config_path = "$CODEX_CONFIG"
wrapper = "$WRAPPER_SCRIPT"

with open(config_path) as f:
    content = f.read()

new_notify = f'notify = ["{wrapper}", "turn-ended"]'

# Replace existing notify line or add new one
if re.search(r'^notify\s*=', content, re.MULTILINE):
    content = re.sub(r'^notify\s*=.*$', new_notify, content, flags=re.MULTILINE)
    print("    Updated existing notify line")
else:
    # Add after first non-comment line
    lines = content.split('\n')
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.strip() and not line.strip().startswith('#'):
            insert_idx = i
            break
    lines.insert(insert_idx, new_notify)
    content = '\n'.join(lines)
    print("    Added notify line")

with open(config_path, 'w') as f:
    f.write(content)
print("    Codex config.toml updated.")
PYEOF2

    fi
fi

echo ""
echo "==> Hook setup complete."
echo ""
echo "  Claude Code hooks: UserPromptSubmit → running, Stop → done, Notification → waiting check"
echo "  Codex hooks:       turn-ended → done (via notify wrapper)"
echo ""
echo "  Note: Changes take effect on the next Claude Code / Codex session."
echo "  Note: Codex Desktop App and Claude Code Desktop may require separate validation."
echo ""
echo "  To verify: start a Claude Code session and check 'agent-beacon list'"
