#!/usr/bin/env bash
# Statusline installer (Linux/macOS/WSL) -- deploys statusline script and patches settings.json
#
# Usage: bash statusline/install.sh

set -e

RAW_BASE="https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
DEST_SCRIPT="$CLAUDE_DIR/statusline-command.sh"

[ -f "$SETTINGS" ] || { echo "ERROR: $SETTINGS not found."; exit 1; }

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
fi

# Deploy script
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/statusline-command.sh" ]; then
  cp "$SCRIPT_DIR/statusline-command.sh" "$DEST_SCRIPT"
else
  curl -sL "$RAW_BASE/statusline/statusline-command.sh" -o "$DEST_SCRIPT"
fi
chmod +x "$DEST_SCRIPT"
echo "[+] Deployed statusline-command.sh"

# Patch settings.json
python3 - "$SETTINGS" "$DEST_SCRIPT" <<'PYEOF'
import json, sys
settings_file, script = sys.argv[1], sys.argv[2]
with open(settings_file) as f:
    data = json.load(f)
data["statusLine"] = {
    "type": "command",
    "command": f'bash "{script}"',
    "refreshInterval": 60
}
with open(settings_file, "w") as f:
    json.dump(data, f, indent=2)
print(f"[+] settings.json updated (statusLine -> bash)")
PYEOF
