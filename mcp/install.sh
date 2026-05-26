#!/usr/bin/env bash
# MCP server installer (Linux/macOS/WSL)
# Installs: filesystem, git, fetch, github, svelte at user scope
#
# Usage: bash mcp/install.sh

set -e

echo "[MCP] Installing MCP servers..."

# Check Node.js
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js required. Install from https://nodejs.org"
  exit 1
fi

# Check/install uv
if ! command -v uv >/dev/null 2>&1; then
  echo "[*] uv not found, installing..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.cargo/bin:$PATH"
fi

USER_HOME="$HOME"
DEV_DIR="$HOME/dev"
CLAUDE_JSON="$HOME/.claude.json"

# Read existing mcpServers names (user scope) from ~/.claude.json
existing_mcp=""
if [ -f "$CLAUDE_JSON" ]; then
  if command -v jq >/dev/null 2>&1; then
    existing_mcp="$(jq -r '.mcpServers // {} | keys[]' "$CLAUDE_JSON" 2>/dev/null || true)"
  elif command -v python3 >/dev/null 2>&1; then
    existing_mcp="$(python3 -c 'import json,sys
try:
    with open(sys.argv[1]) as f: d=json.load(f)
    for k in (d.get("mcpServers") or {}): print(k)
except Exception: pass' "$CLAUDE_JSON" 2>/dev/null || true)"
  fi
fi

has_server() {
  printf '%s\n' "$existing_mcp" | grep -Fxq "$1"
}

add_stdio() {
  local name="$1"; shift
  if has_server "$name"; then
    echo "[=] Already configured: $name"
  else
    claude mcp add --scope user "$name" -- "$@"
    echo "[+] $name"
  fi
}

add_http() {
  local name="$1" url="$2"
  if has_server "$name"; then
    echo "[=] Already configured: $name"
  else
    claude mcp add --scope user --transport http "$name" "$url"
    echo "[+] $name (http): $url"
  fi
}

add_stdio filesystem npx -y @modelcontextprotocol/server-filesystem "$USER_HOME" "$DEV_DIR"
add_stdio git        uvx mcp-server-git
add_stdio fetch      uvx mcp-server-fetch
add_stdio github     npx -y @modelcontextprotocol/server-github

# HTTP transport servers
add_http svelte https://mcp.svelte.dev/mcp

echo ""
echo "Done. Restart Claude Code to activate MCP servers."
echo "GitHub MCP needs GITHUB_TOKEN env var set."
