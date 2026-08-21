# claude_skill_everywhere

Personal Claude Code marketplace and sync hub for Noxfen. Cross-platform installer for skills, hooks, and MCP configs.

## Repo purpose

This repo is a **Claude Code plugin marketplace** (registered via `extraKnownMarketplaces`).  
It also distributes hooks and registers external marketplaces from `sources.json`.

## Structure

```
plugins/noxfen-essentials/   <- main plugin (skills only)
  .claude-plugin/plugin.json <- plugin manifest
  skills/                    <- SKILL.md files (auto-loaded by Claude when installed)
hooks/                       <- hook scripts + installers
  install.ps1 / install.sh   <- registers all hooks into ~/.claude/settings.json
  lint-on-edit.*             <- PostToolUse: auto-format on Write/Edit
  dep-audit.*                <- PostToolUse: run cargo/npm/pip-audit on dep file changes
  update-docs-reminder.*     <- Stop: remind to update CLAUDE.md/README.md (current turn only)
  run-tests-on-stop.*        <- Stop: run test suite after file edits; inject failures
  auto-sync.*                <- SessionStart: git pull every known checkout (env CLAUDE_SKILL_EVERYWHERE_DIR, marketplace clone, ~/claude_skill_everywhere)
  unsafe-rust-blocker.*      <- PreToolUse: block unsafe {} in .rs without // SAFETY: comment
  branch-context-injector.*  <- UserPromptSubmit: inject git branch + dirty count into prompts
  installer-sync-reminder.*  <- Stop: remind to update install.* if hooks/mcp/statusline/sources.json edited
mcp/
  install.ps1 / install.sh   <- installs MCP servers (filesystem, git, fetch, github, svelte)
  README.md
statusline/
  statusline-command.ps1/.sh <- 5h/7d rate-limit bars for Claude Code statusline
  install.ps1 / install.sh   <- deploys statusline + patches settings.json
sources.json                 <- external marketplaces + recommended plugins to register on install
install.ps1 / install.sh     <- root one-shot installer (marketplace + statusline + MCP + hooks + plugins)
```

## Adding a new skill

1. Create `plugins/noxfen-essentials/skills/<skill-name>/SKILL.md`
2. Frontmatter: `name`, `description` (trigger conditions), `version`
3. Commit + push
4. On any device: `/plugin update noxfen-essentials@noxfen`

## Adding a new hook

1. Create the script in `hooks/` (both `.ps1` and `.sh`)
2. Register it in `hooks/install.ps1` and `hooks/install.sh`
3. Commit + push
4. On any device: re-run `install.ps1` or `install.sh`

## Adding an external marketplace

Edit `sources.json` → add entry to `external_marketplaces` → commit + push → re-run installer.

## Adding an MCP server

1. Add the server to BOTH `mcp/install.ps1` (`$Servers`/`$HttpServers` arrays) and `mcp/install.sh` (`add_stdio`/`add_http` calls)
2. Add a row to the tables in `mcp/README.md` and root `README.md`
3. Commit + push → re-run installer on each device (idempotent, skips already-configured servers)

## Conventions

- Scripts: PowerShell 7+ for Windows (`.ps1`), Bash for Linux/macOS (`.sh`) — always both
- Hooks: always exit 0 unless returning feedback to Claude (exit 2 = inject message via **stderr**, not stdout)
- Skills: description field drives when Claude auto-activates the skill — be specific
- Dependencies: python3 required by hooks and the hooks/statusline installers; jq required by `statusline-command.sh`; `install.sh` uses jq with python3 fallback

## Install (one-liner)

```powershell
# Windows
irm https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.ps1 | iex
```
```bash
# Linux/WSL
bash <(curl -sL https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.sh)
```
