#Requires -Version 7.0
#!/usr/bin/env pwsh
# SessionStart hook -- auto-pull claude_skill_everywhere repo on session start

$RepoDir = $env:CLAUDE_SKILL_EVERYWHERE_DIR ?? (Join-Path $env:USERPROFILE "claude_skill_everywhere")

if (-not (Test-Path (Join-Path $RepoDir ".git"))) { exit 0 }

$result = git -C $RepoDir pull --ff-only --quiet 2>&1
if ($LASTEXITCODE -ne 0) { exit 0 }

if ($result -and $result -notmatch "Already up to date") {
    Write-Output "[claude_skill_everywhere] Updated from remote. New skills/hooks available."
}

exit 0
