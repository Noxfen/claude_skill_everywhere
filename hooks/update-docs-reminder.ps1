#Requires -Version 7.0
#!/usr/bin/env pwsh
# Stop hook -- remind Claude to update CLAUDE.md / README.md after file edits

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data -or $data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$lines = Get-Content $transcriptPath -Encoding utf8 -ErrorAction SilentlyContinue
if (-not $lines) { exit 0 }

# Find last user message — Write/Edit after it = current turn only
$lastUserIdx = -1
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match '"type":"user"') { $lastUserIdx = $i; break }
}
$hasEdit = $false
for ($i = $lastUserIdx + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '"name":\s*"(Write|Edit)"') { $hasEdit = $true; break }
}
if (-not $hasEdit) { exit 0 }

$workDir = if ($data.cwd -and (Test-Path $data.cwd)) { $data.cwd } else { Get-Location }
$gitRoot = git -C $workDir rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitRoot) { exit 0 }
$gitRoot = $gitRoot.Trim()

$docs = @(
    "CLAUDE.md", "README.md"
) | Where-Object { Test-Path (Join-Path $gitRoot $_) }

if ($docs.Count -eq 0) { exit 0 }

[Console]::Error.WriteLine("You just modified project files. Check whether $($docs -join ', ') needs updating to reflect the changes. If so, update them now.")
exit 2
