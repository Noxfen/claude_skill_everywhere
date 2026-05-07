#!/usr/bin/env bash
# claude_skill_everywhere — hook installer (Linux/macOS/WSL)
# Registers update-docs-reminder (Stop) and auto-sync (SessionStart) into settings.json
#
# Usage (remote):
#   bash <(curl -sL https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/hooks/install.sh)
# Usage (local):
#   bash hooks/install.sh [--force]

set -e

REPO_OWNER="Noxfen"
REPO_NAME="claude_skill_everywhere"
RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main"

FORCE=0
for arg in "$@"; do case "$arg" in --force|-f) FORCE=1 ;; esac; done

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"

[ -f "$SETTINGS" ] || { echo "ERROR: $SETTINGS not found."; exit 1; }

mkdir -p "$HOOKS_DIR"

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
fi

get_hook_file() {
  local name="$1"
  local dest="$HOOKS_DIR/$name"
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$name" ]; then
    cp "$SCRIPT_DIR/$name" "$dest"
  else
    curl -sL "$RAW_BASE/hooks/$name" -o "$dest"
  fi
  chmod +x "$dest"
  echo "[+] Installed hook script: $name"
}

get_hook_file "update-docs-reminder.sh"
get_hook_file "run-tests-on-stop.sh"
get_hook_file "compact-warning.sh"
get_hook_file "track-context.sh"
get_hook_file "auto-sync.sh"
get_hook_file "lint-on-edit.sh"
get_hook_file "branch-context-injector.sh"
get_hook_file "unsafe-rust-blocker.sh"
get_hook_file "dep-audit.sh"

# Patch settings.json using python3
python3 - "$SETTINGS" "$HOOKS_DIR" "$FORCE" <<'PYEOF'
import json, sys, os

settings_file, hooks_dir, force = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

with open(settings_file) as f:
    data = json.load(f)

data.setdefault("hooks", {})

def add_hook(event, command):
    data["hooks"].setdefault(event, [])
    basename = os.path.basename(command.split('"')[-2] if '"' in command else command)
    already = any(
        any(basename in h.get("command", "") for h in entry.get("hooks", []))
        for entry in data["hooks"][event]
    )
    if not already or force:
        data["hooks"][event].append({"hooks": [{"type": "command", "command": command}]})
        print(f"[+] Registered hook: {event} -> {command}")
    else:
        print(f"[=] Hook already registered: {event}")

docs_cmd    = f'bash "{hooks_dir}/update-docs-reminder.sh"'
tests_cmd   = f'bash "{hooks_dir}/run-tests-on-stop.sh"'
compact_cmd = f'bash "{hooks_dir}/compact-warning.sh"'
sync_cmd    = f'bash "{hooks_dir}/auto-sync.sh"'
lint_cmd    = f'bash "{hooks_dir}/lint-on-edit.sh"'
ctx_cmd     = f'bash "{hooks_dir}/track-context.sh"'
audit_cmd   = f'bash "{hooks_dir}/dep-audit.sh"'
unsafe_cmd  = f'bash "{hooks_dir}/unsafe-rust-blocker.sh"'
branch_cmd  = f'bash "{hooks_dir}/branch-context-injector.sh"'

add_hook("Stop", docs_cmd)
add_hook("Stop", tests_cmd)
add_hook("Stop", compact_cmd)
add_hook("SessionStart", sync_cmd)
add_hook("PostToolUse", lint_cmd)
add_hook("PostToolUse", ctx_cmd)
add_hook("PostToolUse", audit_cmd)
add_hook("PreToolUse", unsafe_cmd)
add_hook("UserPromptSubmit", branch_cmd)

with open(settings_file, "w") as f:
    json.dump(data, f, indent=2)
PYEOF

echo ""
echo "Hooks installed. Restart Claude Code to activate."
