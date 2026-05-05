# MCP Servers

Recommended MCP servers. Install with the installer or manually via `claude mcp add --scope user`.

## Quick install (all at once)

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File mcp\install.ps1
```
```bash
# Linux/WSL
bash mcp/install.sh
```

## Servers included

| Name | Command | Purpose |
|------|---------|---------|
| `filesystem` | `npx @modelcontextprotocol/server-filesystem` | Read/write files outside cwd |
| `git` | `uvx mcp-server-git` | Query git history, diff, blame |
| `fetch` | `uvx mcp-server-fetch` | HTTP GET/POST for API testing |
| `github` | `npx @modelcontextprotocol/server-github` | Issues, PRs, branches via API |

## GitHub MCP auth

Set env var before starting Claude Code:
```powershell
$env:GITHUB_TOKEN = "ghp_your_token_here"
```
Or add to system environment variables permanently.

## Filesystem paths

Default: `C:\Users\<you>` and `D:\dev` (Windows) / `$HOME` and `$HOME/dev` (Linux).
Edit `mcp/install.ps1` or `mcp/install.sh` to add more allowed paths.
