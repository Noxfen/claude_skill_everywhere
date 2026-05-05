#!/usr/bin/env bash
# claude_skill_everywhere — Linux/macOS installer
# Registers this marketplace + all external marketplaces from sources.json
# into ~/.claude/settings.json
#
# Usage (remote):
#   bash <(curl -sL https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.sh)
# Usage (local clone):
#   bash install.sh [--force]

set -e

REPO_OWNER="Noxfen"
REPO_NAME="claude_skill_everywhere"
MARKET_KEY="noxfen"
RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main"

FORCE=0
for arg in "$@"; do
  case "$arg" in --force|-f) FORCE=1 ;; esac
done

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

echo ""
echo "claude_skill_everywhere installer"
echo "==================================="
echo ""

# --- Check settings.json ---
if [ ! -f "$SETTINGS" ]; then
  echo "ERROR: $SETTINGS not found. Is Claude Code installed?"
  exit 1
fi

# --- Pick JSON tool ---
if command -v jq >/dev/null 2>&1; then
  JSON_TOOL="jq"
elif command -v python3 >/dev/null 2>&1; then
  JSON_TOOL="python3"
else
  echo "ERROR: need 'jq' or 'python3' to modify settings.json"
  exit 1
fi

json_merge() {
  # Args: <settings_file> <key> <repo>
  # Adds extraKnownMarketplaces.<key> = { source: { source: "github", repo: <repo> } }
  local file="$1" key="$2" repo="$3"

  if [ "$JSON_TOOL" = "jq" ]; then
    local tmp
    tmp=$(mktemp)
    jq --arg key "$key" --arg repo "$repo" \
      '.extraKnownMarketplaces //= {} | .extraKnownMarketplaces[$key] = {source: {source: "github", repo: $repo}}' \
      "$file" > "$tmp" && mv "$tmp" "$file"
  else
    python3 - "$file" "$key" "$repo" <<'PYEOF'
import json, sys
file, key, repo = sys.argv[1], sys.argv[2], sys.argv[3]
with open(file) as f:
    data = json.load(f)
data.setdefault("extraKnownMarketplaces", {})[key] = {"source": {"source": "github", "repo": repo}}
with open(file, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
  fi
}

key_exists() {
  local file="$1" key="$2"
  if [ "$JSON_TOOL" = "jq" ]; then
    jq -e --arg key "$key" '.extraKnownMarketplaces[$key]' "$file" >/dev/null 2>&1
  else
    python3 - "$file" "$key" <<'PYEOF'
import json, sys
file, key = sys.argv[1], sys.argv[2]
with open(file) as f:
    data = json.load(f)
sys.exit(0 if key in data.get("extraKnownMarketplaces", {}) else 1)
PYEOF
  fi
}

# --- Register this repo as a marketplace ---
if ! key_exists "$SETTINGS" "$MARKET_KEY" || [ "$FORCE" = "1" ]; then
  json_merge "$SETTINGS" "$MARKET_KEY" "$REPO_OWNER/$REPO_NAME"
  echo "[+] Registered marketplace: $MARKET_KEY ($REPO_OWNER/$REPO_NAME)"
else
  echo "[=] Marketplace already registered: $MARKET_KEY"
fi

# --- Load sources.json ---
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
fi

SOURCES_FILE=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/sources.json" ]; then
  SOURCES_FILE="$SCRIPT_DIR/sources.json"
else
  TMP_SOURCES=$(mktemp)
  if curl -sL "$RAW_BASE/sources.json" -o "$TMP_SOURCES" 2>/dev/null && [ -s "$TMP_SOURCES" ]; then
    SOURCES_FILE="$TMP_SOURCES"
  else
    echo "[!] Could not fetch sources.json — skipping external marketplaces"
  fi
fi

# --- Register external marketplaces ---
if [ -n "$SOURCES_FILE" ]; then
  if [ "$JSON_TOOL" = "jq" ]; then
    while IFS=$'\t' read -r name repo; do
      if ! key_exists "$SETTINGS" "$name" || [ "$FORCE" = "1" ]; then
        json_merge "$SETTINGS" "$name" "$repo"
        echo "[+] Registered external marketplace: $name ($repo)"
      else
        echo "[=] Already registered: $name"
      fi
    done < <(jq -r '.external_marketplaces[] | [.name, .repo] | @tsv' "$SOURCES_FILE")
  else
    python3 - "$SOURCES_FILE" "$SETTINGS" "$FORCE" <<'PYEOF'
import json, sys, subprocess

sources_file, settings_file, force = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

with open(sources_file) as f:
    sources = json.load(f)
with open(settings_file) as f:
    settings = json.load(f)

settings.setdefault("extraKnownMarketplaces", {})

for ext in sources.get("external_marketplaces", []):
    key, repo = ext["name"], ext["repo"]
    if key not in settings["extraKnownMarketplaces"] or force:
        settings["extraKnownMarketplaces"][key] = {"source": {"source": "github", "repo": repo}}
        print(f"[+] Registered external marketplace: {key} ({repo})")
    else:
        print(f"[=] Already registered: {key}")

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)
PYEOF
  fi
fi

# --- Install MCP servers ---
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/mcp/install.sh" ]; then
  bash "$SCRIPT_DIR/mcp/install.sh" || echo "[!] MCP installer failed"
else
  TMP_MCP=$(mktemp)
  if curl -sL "$RAW_BASE/mcp/install.sh" -o "$TMP_MCP"; then
    bash "$TMP_MCP" || echo "[!] MCP installer failed"
    rm -f "$TMP_MCP"
  else
    echo "[!] Could not fetch mcp/install.sh -- skipping MCP servers"
  fi
fi

# --- Install hooks ---
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/hooks/install.sh" ]; then
  bash "$SCRIPT_DIR/hooks/install.sh" $([ "$FORCE" = "1" ] && echo "--force")
else
  TMP_HOOK=$(mktemp)
  if curl -sL "$RAW_BASE/hooks/install.sh" -o "$TMP_HOOK"; then
    bash "$TMP_HOOK" $([ "$FORCE" = "1" ] && echo "--force")
    rm -f "$TMP_HOOK"
  else
    echo "[!] Could not fetch hooks/install.sh — skipping hooks"
  fi
fi

echo ""
echo "Done!"
echo ""
echo "Next steps in Claude Code:"
echo "  /plugin discover                          -> browse available plugins"
echo "  /plugin install noxfen-essentials@noxfen  -> install skills"
echo ""
echo "To sync after updating sources.json, re-run this installer."
