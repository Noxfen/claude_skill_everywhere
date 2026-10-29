# MCP Servers

Recommended MCP servers. Install with the installer or manually via `claude mcp add --scope user`.

## Quick install (all at once)

```powershell
# Windows
pwsh -File mcp\install.ps1
```
```bash
# Linux/WSL
bash mcp/install.sh
```

## Servers included

| Name | Command | Purpose |
|------|---------|---------|
| `filesystem` | `npx @modelcontextprotocol/server-filesystem` | Read/write files outside cwd |
| `git` | `uvx --with 'mcp<2' mcp-server-git` | Query git history, diff, blame |
| `fetch` | `uvx --with 'mcp<2' mcp-server-fetch` | Fetch a URL and return its content (no method/body parameters) |
| `github` | `npx @modelcontextprotocol/server-github` | Issues, PRs, branches via API |
| `svelte` | HTTP `https://mcp.svelte.dev/mcp` | Official Svelte/SvelteKit docs + Svelte 5 runes |
| `rea` | `rea mcp` (Windows: via WSL if not native) | Reverse engineering of binaries, apps, web bundles — registered only if `rea-agents` is installed |

## GitHub MCP auth

Set env var before starting Claude Code:
```powershell
$env:GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_your_token_here"
```
Or add to system environment variables permanently.

## Filesystem paths

Default: `C:\Users\<you>` and `D:\dev` (Windows) / `$HOME` and `$HOME/dev` (Linux).
Set `CLAUDE_SKILL_DEV_DIR` before running the installer to override the dev directory
(first install only — already-configured servers are skipped).
Edit `mcp/install.ps1` or `mcp/install.sh` to add more allowed paths.

The `git`/`fetch` servers pin the `mcp` SDK below 2.0 (SDK 2.0.0 renamed
`McpError` → `MCPError`, breaking `mcp-server-fetch`). Drop the `--with 'mcp<2'`
once upstream is compatible with `mcp>=2`.

## rea (optional)

Reverse-engineering MCP server ([morluto/rea](https://github.com/morluto/rea), npm `rea-agents`, MIT).
The installer registers it only when `rea` is already installed — it never runs `npm install` for you.

```bash
npm install -g rea-agents
```

On Windows the installer prefers a native `rea`; otherwise it uses a WSL install via
`wsl.exe [-d <distro>] -- bash -lc "exec rea mcp"`. Set `CLAUDE_SKILL_REA_WSL_DISTRO`
(e.g. `Ubuntu-24.04`) to pick the distro; unset = default WSL distro.
