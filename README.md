# claude_skill_everywhere

Personal Claude Code marketplace — skills, commands, hooks, and MCP configs by Noxfen.  
Installable with one command. Syncs across all machines via Git.

## Install

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.ps1 | iex
```

**Linux / macOS / WSL:**
```bash
bash <(curl -sL https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.sh)
```

The installer:
1. Registers this repo as a Claude Code marketplace (`noxfen`)
2. Registers all external marketplaces listed in `sources.json`
3. Leaves existing settings untouched

After installing, open Claude Code and run:
```
/plugin install noxfen-essentials@noxfen
```

## Sync across machines

On any machine — after `git pull` or when `sources.json` changes — re-run the install script.  
It's idempotent: already-registered entries are skipped.

## Add external marketplaces

Edit `sources.json`:
```json
{
  "external_marketplaces": [
    {
      "name": "some-marketplace",
      "repo": "username/repo-name",
      "description": "What it contains"
    }
  ]
}
```

Commit, push, then re-run the installer on each machine.

## Structure

```
plugins/
  noxfen-essentials/        <- personal plugin (skills, commands)
hooks/                      <- standalone hook scripts
sources.json                <- external marketplace manifest
install.ps1                 <- Windows installer
install.sh                  <- Linux/macOS installer
```

## Add your own skills

Place `.md` skill files in `plugins/noxfen-essentials/skills/`.  
Commit, push, then in Claude Code: `/plugin update noxfen-essentials@noxfen`.

## Useful references

- [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) — curated skills/hooks list
- [Claude Code plugin docs](https://code.claude.com/docs/en/plugins)
- [Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide)
