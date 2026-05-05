# claude_skill_everywhere

Personal Claude Code marketplace by Noxfen — skills, hooks, and MCP configs.  
One command installs everything on any machine.

## Install

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.ps1 | iex
```

**Linux / macOS / WSL:**
```bash
bash <(curl -sL https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.sh)
```

The installer does:
1. Registers `noxfen` marketplace + external marketplaces from `sources.json`
2. Installs MCP servers: `filesystem`, `git`, `fetch`, `github`
3. Installs hooks: `lint-on-edit` (PostToolUse), `auto-sync` (SessionStart), `update-docs-reminder` (Stop)

After installing, restart Claude Code, then:
```
/plugin install noxfen-essentials@noxfen
```

---

## Prerequisites

### Windows

| Tool | Min | Required for | Install |
|------|-----|-------------|---------|
| Claude Code | latest | everything | `winget install Anthropic.ClaudeCode` |
| **PowerShell 7** | **7.0+** | **all hook scripts (required)** | **`winget install Microsoft.PowerShell`** |
| Git | 2.x | installer, auto-sync hook | `winget install Git.Git` |
| Node.js | 18+ | MCP servers (filesystem, github, fetch) | `winget install OpenJS.NodeJS` |
| Python | 3.10+ | uv + Python-based MCP servers | `winget install Python.Python.3.11` |
| PowerShell | 5.1+ | hooks | built-in on Windows 10/11 |
| PSScriptAnalyzer | 1.x | lint-on-edit for `.ps1` | **auto-installed** by installer |
| uv | any | MCP git/fetch servers | **auto-installed** by installer (`pip install uv`) |
| shellcheck | any | lint-on-edit for `.sh` | `winget install koalaman.shellcheck` |
| ruff | any | lint-on-edit for `.py` | `pip install ruff` |
| rustup / cargo | 1.x | Rust projects | `winget install Rustlang.Rustup` |
| clangd | any | `clangd-lsp` plugin, lint `.c/.h` | `winget install LLVM.LLVM` |
| pyright | any | `pyright-lsp` plugin | `npm install -g pyright` |

### Linux / macOS / WSL

| Tool | Min | Required for | Install |
|------|-----|-------------|---------|
| Claude Code | latest | everything | `npm install -g @anthropic-ai/claude-code` |
| Git | 2.x | installer, auto-sync hook | `apt install git` |
| Node.js | 18+ | MCP servers (filesystem, github, fetch) | `apt install nodejs` or [nvm](https://github.com/nvm-sh/nvm) |
| Python | 3.10+ | uv + Python-based MCP servers | `apt install python3` |
| Bash | 4+ | hooks | built-in |
| uv | any | MCP git/fetch servers | **auto-installed** by installer |
| jq | any | `install.sh` JSON parsing (fallback: python3) | `apt install jq` |
| shellcheck | any | lint-on-edit for `.sh` | `apt install shellcheck` |
| ruff | any | lint-on-edit for `.py` | `pip install ruff` |
| rustup / cargo | 1.x | Rust projects | [rustup.rs](https://rustup.rs) |
| clangd | any | `clangd-lsp` plugin, lint `.c/.h` | `apt install clangd` |
| pyright | any | `pyright-lsp` plugin | `npm install -g pyright` |

**Bold** = installed automatically by the installer. All others are optional — missing tools are silently skipped by hooks.

---

## Recommended plugins

Install in Claude Code after running the installer:

| Plugin | Marketplace | Command | What it does |
|--------|------------|---------|-------------|
| `noxfen-essentials` | noxfen | `/plugin install noxfen-essentials@noxfen` | Skills: Rust/Python/JS/C/Bash/PS best practices, orchestrator, debug |
| `rust-analyzer-lsp` | claude-plugins-official | `/plugin install rust-analyzer-lsp@claude-plugins-official` | Rust LSP (diagnostics, completions) |
| `clangd-lsp` | claude-plugins-official | `/plugin install clangd-lsp@claude-plugins-official` | C/C++ LSP |
| `pyright-lsp` | claude-plugins-official | `/plugin install pyright-lsp@claude-plugins-official` | Python type checking LSP |
| `code-review` | claude-plugins-official | `/plugin install code-review@claude-plugins-official` | Automated PR review (`/code-review`) |
| `commit-commands` | claude-plugins-official | `/plugin install commit-commands@claude-plugins-official` | `/commit`, `/push`, `/pr` commands |
| `hookify` | claude-plugins-official | `/plugin install hookify@claude-plugins-official` | Create hooks from markdown |
| `feature-dev` | claude-plugins-official | `/plugin install feature-dev@claude-plugins-official` | Structured 7-phase feature development |
| `caveman` | caveman | `/plugin install caveman@caveman` | Ultra-compressed mode (~75% token reduction) |

---

## What the installer sets up

### Hooks (auto-applied to `~/.claude/settings.json`)

| Hook | Event | What it does |
|------|-------|-------------|
| `lint-on-edit` | PostToolUse | Auto-formats/lints after every Write/Edit: `rustfmt`, `ruff`, `prettier`, `clang-format`, `shellcheck`, `PSScriptAnalyzer` |
| `auto-sync` | SessionStart | `git pull` this repo at session start — keeps skills/hooks updated |
| `update-docs-reminder` | Stop | Reminds Claude to update `CLAUDE.md`/`README.md` after file edits |

### MCP servers (user scope)

| Server | Command | Purpose |
|--------|---------|---------|
| `filesystem` | `npx @modelcontextprotocol/server-filesystem` | Read/write files in `~/` and `~/dev` |
| `git` | `uvx mcp-server-git` | Query git history, diff, blame on any repo |
| `fetch` | `uvx mcp-server-fetch` | HTTP GET/POST for API testing |
| `github` | `npx @modelcontextprotocol/server-github` | Issues, PRs, branches (needs `GITHUB_TOKEN`) |

**GitHub MCP token** — set before starting Claude Code:
```powershell
# Windows — permanent
[System.Environment]::SetEnvironmentVariable("GITHUB_TOKEN","ghp_...", "User")
```
```bash
# Linux -- add to ~/.bashrc or ~/.profile
export GITHUB_TOKEN="ghp_..."
```

---

## Sync across machines

Add new skills/hooks/external repos → commit → push.  
On other machines: re-run the install script (idempotent, skips already-registered entries).

The `auto-sync` hook runs `git pull` at every session start automatically.

---

## Structure

```
.claude-plugin/
  marketplace.json          <- Claude Code marketplace manifest
plugins/
  noxfen-essentials/        <- main plugin
    .claude-plugin/
      plugin.json
    skills/                 <- SKILL.md files
      rust-best-practices/
      python-best-practices/
      js-best-practices/
      c-best-practices/
      bash-best-practices/
      powershell-best-practices/
      orchestrator/
      plan-execute/
      debug/
hooks/
  lint-on-edit.ps1 / .sh   <- PostToolUse: auto-format on Write/Edit
  update-docs-reminder.ps1 / .sh  <- Stop: remind to update docs
  auto-sync.ps1 / .sh      <- SessionStart: git pull this repo
  install.ps1 / .sh        <- registers hooks into settings.json
mcp/
  install.ps1 / .sh        <- installs MCP servers
  README.md
sources.json                <- external marketplaces + recommended plugins
install.ps1 / .sh          <- root one-shot installer
```

## Add a new skill

1. Create `plugins/noxfen-essentials/skills/<name>/SKILL.md`
2. Frontmatter: `name`, `description` (trigger conditions), `version`
3. Commit + push
4. On any device: `/plugin update noxfen-essentials@noxfen`

## Add an external marketplace

Edit `sources.json` → add to `external_marketplaces` → commit + push → re-run installer.
