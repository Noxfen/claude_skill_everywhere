#!/usr/bin/env pwsh
# SessionStart hook — auto-pulls claude_skill_everywhere repo to stay in sync
# Install: run hooks/install.ps1 (registered automatically)

$RepoDir = if ($env:CLAUDE_SKILL_EVERYWHERE_DIR) {
    $env:CLAUDE_SKILL_EVERYWHERE_DIR
} else {
    Join-Path $env:USERPROFILE "claude_skill_everywhere"
}

if (-not (Test-Path (Join-Path $RepoDir ".git"))) { exit 0 }

$result = & git -C $RepoDir pull --ff-only --quiet 2>&1
if ($LASTEXITCODE -ne 0) {
    # Silent fail — don't block the session
    exit 0
}

# If there were updates, notify
if ($result -and $result -notmatch "Already up to date") {
    Write-Output "[claude_skill_everywhere] Updated from remote. New skills/hooks available."
}

exit 0
