#Requires -Version 7.0
#!/usr/bin/env pwsh
# UserPromptSubmit hook -- inject terse git status into every prompt
# Output goes to stdout, gets appended to user's prompt as additional context.
# Skips silently if not in a git repo or if disabled via $env:CLAUDE_NO_GIT_CTX=1.

trap { exit 0 }

if ($env:CLAUDE_NO_GIT_CTX -eq "1") { exit 0 }

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data) { exit 0 }

$workDir = if ($data.cwd -and (Test-Path $data.cwd)) { $data.cwd } else { Get-Location }
$branch = git -C $workDir branch --show-current 2>$null
if ($LASTEXITCODE -ne 0 -or -not $branch) { exit 0 }
$branch = $branch.Trim()

$status = git -C $workDir status --porcelain 2>$null
$modified = 0; $untracked = 0
if ($status) {
    foreach ($line in ($status -split "`n")) {
        if ($line -match '^\?\?') { $untracked++ }
        elseif ($line.Trim()) { $modified++ }
    }
}

$parts = @("git: $branch")
if ($modified -gt 0)  { $parts += "$modified modified" }
if ($untracked -gt 0) { $parts += "$untracked untracked" }

Write-Output "[$($parts -join ' | ')]"
exit 0
