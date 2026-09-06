#Requires -Version 7.0
#!/usr/bin/env pwsh
# Stop hook -- remind Claude to update CLAUDE.md / README.md after file edits

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data -or $data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$lines = Get-Content $transcriptPath -Encoding utf8 -ErrorAction SilentlyContinue
if (-not $lines) { exit 0 }

# Find last REAL user prompt — Write/Edit after it = current turn only.
# Regex is a cheap prefilter (tolerant of JSON whitespace); candidates are
# parsed as JSON so a prompt merely mentioning tool_result, or a structural
# tool_result entry (also "type":"user"), is classified correctly.
$lastUserIdx = -1
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '"type"\s*:\s*"user"') { continue }
    $rec = $null
    try { $rec = $lines[$i] | ConvertFrom-Json -ErrorAction Stop } catch {}
    if ($rec) {
        if ($rec.type -ne 'user') { continue }
        $content = $rec.message?.content
        $isToolResult = $false
        if ($content -is [System.Array]) {
            foreach ($c in $content) { if ($c.type -eq 'tool_result') { $isToolResult = $true; break } }
        }
        if (-not $isToolResult) { $lastUserIdx = $i; break }
    } elseif ($lines[$i] -notmatch '"tool_result"') { $lastUserIdx = $i; break }
}
$hasEdit = $false
for ($i = $lastUserIdx + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch '"name"\s*:\s*"(Write|Edit)"') { continue }
    $rec = $null
    try { $rec = $lines[$i] | ConvertFrom-Json -ErrorAction Stop } catch { $hasEdit = $true; break }
    $content = $rec.message?.content
    if ($content -is [System.Array]) {
        foreach ($c in $content) {
            if ($c.type -eq 'tool_use' -and @('Write','Edit') -contains $c.name) { $hasEdit = $true; break }
        }
    }
    if ($hasEdit) { break }
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
