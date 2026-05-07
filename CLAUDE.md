# claude_skill_everywhere

Personal Claude Code marketplace and sync hub for Noxfen. Cross-platform installer for skills, hooks, and MCP configs.

## Repo purpose

This repo is a **Claude Code plugin marketplace** (registered via `extraKnownMarketplaces`).  
It also distributes hooks and registers external marketplaces from `sources.json`.

## Structure

```
plugins/noxfen-essentials/   <- main plugin (skills, commands, agents)
  .claude-plugin/plugin.json <- plugin manifest
  skills/                    <- SKILL.md files (auto-loaded by Claude when installed)
hooks/                       <- hook scripts + installers
  install.ps1 / install.sh   <- registers all hooks into ~/.claude/settings.json
  lint-on-edit.*             <- PostToolUse: auto-format on Write/Edit
  track-context.*            <- PostToolUse: estimate context window usage → context-estimate.json
  dep-audit.*                <- PostToolUse: run cargo/npm/pip-audit on dep file changes
  update-docs-reminder.*     <- Stop: remind to update CLAUDE.md/README.md (current turn only)
  run-tests-on-stop.*        <- Stop: run test suite after file edits; inject failures
  compact-warning.*          <- Stop: warn when context estimate >80%
  auto-sync.*                <- SessionStart: git pull this repo
  unsafe-rust-blocker.*      <- PreToolUse: block unsafe {} in .rs without // SAFETY: comment
  branch-context-injector.*  <- UserPromptSubmit: inject git branch + dirty count into prompts
statusline/
  statusline-command.ps1/.sh <- rate-limit + context bar for Claude Code statusline
sources.json                 <- external marketplaces to register on install
install.ps1 / install.sh     <- root one-shot installer (marketplace + hooks)
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

## Conventions

- Scripts: PowerShell for Windows (`.ps1`), Bash for Linux/macOS (`.sh`) — always both
- Hooks: always exit 0 unless returning feedback to Claude (exit 2 = inject message via **stderr**, not stdout)
- Skills: description field drives when Claude auto-activates the skill — be specific
- No dependencies beyond what Claude Code ships: PowerShell, bash, python3 or jq for JSON

## Install (one-liner)

```powershell
# Windows
irm https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.ps1 | iex
```
```bash
# Linux/WSL
bash <(curl -sL https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.sh)
```
