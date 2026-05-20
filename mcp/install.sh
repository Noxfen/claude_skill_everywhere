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

claude mcp add --scope user filesystem -- npx -y @modelcontextprotocol/server-filesystem "$USER_HOME" "$DEV_DIR"
echo "[+] filesystem"

claude mcp add --scope user git -- uvx mcp-server-git
echo "[+] git"

claude mcp add --scope user fetch -- uvx mcp-server-fetch
echo "[+] fetch"

claude mcp add --scope user github -- npx -y @modelcontextprotocol/server-github
echo "[+] github"

# HTTP transport servers
claude mcp add --scope user --transport http svelte https://mcp.svelte.dev/mcp
echo "[+] svelte (http): https://mcp.svelte.dev/mcp"

echo ""
echo "Done. Restart Claude Code to activate MCP servers."
echo "GitHub MCP needs GITHUB_TOKEN env var set."
