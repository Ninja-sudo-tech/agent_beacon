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
beacon_cli = "$(which agent-beacon 2>/dev/null || echo '$HOME/.local/bin/agent-beacon')"
notify_hook = "$(which agent-beacon-claude-notify 2>/dev/null || echo '$HOME/.local/bin/agent-beacon-claude-notify')"

with open(path) as f:
    settings = json.load(f)

if "hooks" not in settings:
    settings["hooks"] = {}

def add_hook(event, command_str, label):
    lst = settings["hooks"].setdefault(event, [])
    if not any("agent-beacon" in str(h) for h in lst):
        lst.append({"hooks": [{"type": "command", "command": command_str}]})
        print(f"    Added {event} hook ({label})")
    else:
        print(f"    {event} hook already present, skipped")

# Background pattern: (cat>/dev/null; agent-beacon ...) &  — the hook shell
# exits immediately so Claude doesn't wait on it (~100-200ms saved per call).
# Used for everything except PermissionRequest (Claude is already paused for
# user input, no latency cost to being synchronous) and Stop (last hook in
# the turn — nothing waits on it, and synchronous execution avoids a race
# where a background write lands after the watcher's next poll, which can
# leave the light stuck on the wrong color).
def bg(cmd):
    return f"(cat>/dev/null; {cmd} 2>/dev/null) &"

def sync(cmd):
    return f"{cmd} 2>/dev/null; cat>/dev/null"

# running when user submits a prompt
add_hook("UserPromptSubmit",
         bg(f"{beacon_cli} set claude running '处理中'"),
         "running")

# waiting when Claude needs permission to run a tool (dedicated hook event)
add_hook("PermissionRequest",
         sync(f"{beacon_cli} set claude waiting '等待权限确认'"),
         "waiting — permission dialog")

# running again once a tool finishes (resumes after a permission approval)
add_hook("PostToolUse",
         bg(f"{beacon_cli} set claude running '处理中'"),
         "running — resumed after tool/permission")

# done when session stops — synchronous, see comment above
add_hook("Stop",
         sync(f"{beacon_cli} set claude done '已完成'"),
         "done")


with open(path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("    Claude Code settings.json updated.")
PYEOF

fi

echo ""

# ──────────────────────────────────────────────
# Codex hooks — hooks.json (interactive terminal + exec)
# ──────────────────────────────────────────────

echo "--- Codex ($(codex --version 2>/dev/null || echo 'not found')) ---"

CODEX_HOME="$HOME/.codex"
CODEX_HOOKS_JSON="$CODEX_HOME/hooks.json"
BEACON_BIN="$(which agent-beacon 2>/dev/null || echo "$HOME/.local/bin/agent-beacon")"

if [ ! -d "$CODEX_HOME" ]; then
    echo "    ~/.codex not found, skipping Codex hooks."
else
    # --- hooks.json (lifecycle hooks: UserPromptSubmit, PermissionRequest, Stop) ---
    if [ -f "$CODEX_HOOKS_JSON" ] && grep -q "agent-beacon" "$CODEX_HOOKS_JSON" 2>/dev/null; then
        echo "    ~/.codex/hooks.json already configured, skipped."
    else
        if [ -f "$CODEX_HOOKS_JSON" ]; then
            cp "$CODEX_HOOKS_JSON" "$CODEX_HOOKS_JSON.agent-beacon-backup-$TIMESTAMP"
            echo "    Backup: $CODEX_HOOKS_JSON.agent-beacon-backup-$TIMESTAMP"
        fi

        # IMPORTANT: Codex's hooks require valid JSON on stdout, so every command
        # ends with echo '{"suppressOutput": true}' (also hides hook noise from the
        # Codex chat UI). UserPromptSubmit is backgrounded with & so Codex doesn't
        # wait on agent-beacon's process startup (~100-200ms saved). PermissionRequest
        # stays synchronous (Codex is already paused for user input, no cost). Stop
        # is synchronous too — it's the last hook in a turn, nothing waits on it, and
        # async execution there can race the codex-watcher daemon's next poll and
        # leave the light stuck on the wrong color.
        cat > "$CODEX_HOOKS_JSON" << HOOKEOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [{"type": "command", "command": "$BEACON_BIN set codex running '处理中' >/dev/null 2>&1 & cat>/dev/null; echo '{"suppressOutput": true}'"}]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [{"type": "command", "command": "$BEACON_BIN set codex waiting '等待权限确认' >/dev/null 2>&1; cat>/dev/null; echo '{"suppressOutput": true}'"}]
      }
    ],
    "Stop": [
      {
        "hooks": [{"type": "command", "command": "$BEACON_BIN set codex done '已完成' >/dev/null 2>&1; cat>/dev/null; echo '{"suppressOutput": true}'"}]
      }
    ]
  }
}
HOOKEOF
        echo "    Created ~/.codex/hooks.json"
        echo "    Supported events: UserPromptSubmit→running, PermissionRequest→waiting, Stop→done"
    fi

    # --- config.toml notify (turn-ended fallback, preserves Computer Use client) ---
    if [ -f "$CODEX_CONFIG" ]; then
        BACKUP_CODEX="$CODEX_CONFIG.agent-beacon-backup-$TIMESTAMP"
        [ ! -f "$BACKUP_CODEX" ] && cp "$CODEX_CONFIG" "$BACKUP_CODEX" && echo "    Backup: $BACKUP_CODEX"

        WRAPPER_SCRIPT="$HOME/.local/bin/agent-beacon-codex-notify"
        if grep -q "agent-beacon-codex-notify" "$CODEX_CONFIG" 2>/dev/null; then
            echo "    config.toml notify already configured, skipped."
        else
            cat > "$WRAPPER_SCRIPT" << 'WRAPEOF'
#!/bin/bash
EVENT="${1:-turn-ended}"
BEACON="$HOME/.local/bin/agent-beacon"
case "$EVENT" in
    turn-ended|done|complete) "$BEACON" set codex done "Turn ended" 2>/dev/null & ;;
    error|failed)             "$BEACON" set codex error "Codex error" 2>/dev/null & ;;
    *)                        "$BEACON" set codex done "Notified: $EVENT" 2>/dev/null & ;;
esac
ORIGINAL="/Users/loutengda/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
[ -f "$ORIGINAL" ] && "$ORIGINAL" "$@" 2>/dev/null &
WRAPEOF
            chmod +x "$WRAPPER_SCRIPT"

            python3 << PYEOF2
import re
config_path = "$CODEX_CONFIG"
wrapper = "$WRAPPER_SCRIPT"
with open(config_path) as f:
    content = f.read()
new_notify = f'notify = ["{wrapper}", "turn-ended"]'
if re.search(r'^notify\s*=', content, re.MULTILINE):
    content = re.sub(r'^notify\s*=.*\$', new_notify, content, flags=re.MULTILINE)
else:
    content = new_notify + "\n" + content
with open(config_path, 'w') as f:
    f.write(content)
print("    config.toml notify updated (turn-ended fallback)")
PYEOF2
        fi
    fi
fi

echo ""
echo "==> Hook setup complete."
echo ""
echo "  Claude Code:  UserPromptSubmit→running  Stop→done  Notification→waiting(近似)"
echo "  Codex CLI:    UserPromptSubmit→running  PermissionRequest→waiting  Stop→done"
echo "  Codex notify: turn-ended→done (fallback)"
echo ""
echo "  ⚠️  Codex 终端首次运行时会出现 hook 信任确认对话框，请选择信任以启用自动状态更新。"
echo "  Note: Changes take effect on the next Claude Code / Codex session."
