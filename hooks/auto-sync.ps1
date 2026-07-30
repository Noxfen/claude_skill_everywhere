#Requires -Version 7.0
#!/usr/bin/env pwsh
# SessionStart hook -- auto-pull claude_skill_everywhere checkouts on session start
#
# Checks every known location instead of a single hardcoded default: the old
# version only looked at $env:USERPROFILE\claude_skill_everywhere, which does not
# exist on a machine that clones the repo elsewhere (e.g. D:\dev), so the hook
# silently exited 0 forever. Set CLAUDE_SKILL_EVERYWHERE_DIR to add your dev checkout.

$ClaudeDir = $env:CLAUDE_CONFIG_DIR ?? (Join-Path $env:USERPROFILE ".claude")

$candidates = @(
    $env:CLAUDE_SKILL_EVERYWHERE_DIR
    (Join-Path $ClaudeDir "plugins\marketplaces\Noxfen-claude_skill_everywhere")
    (Join-Path $env:USERPROFILE "claude_skill_everywhere")
) | Where-Object { $_ }

$updated = @()
$seen    = @{}

foreach ($dir in $candidates) {
    if (-not (Test-Path (Join-Path $dir ".git"))) { continue }

    # Deduplicate: the same checkout may be reachable by several of the paths above
    $real = (Resolve-Path $dir -ErrorAction SilentlyContinue)?.Path
    if (-not $real -or $seen.ContainsKey($real)) { continue }
    $seen[$real] = $true

    # Compare HEAD before/after rather than parsing output: `pull --quiet` prints
    # nothing on a successful fast-forward, so the old output test never fired.
    $before = git -C $dir rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { continue }

    git -C $dir pull --ff-only --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { continue }

    $after = git -C $dir rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { continue }

    if ($before -ne $after) { $updated += $dir }
}

if ($updated.Count -gt 0) {
    Write-Output "[claude_skill_everywhere] Updated from remote: $($updated -join ' ')"
}

exit 0
