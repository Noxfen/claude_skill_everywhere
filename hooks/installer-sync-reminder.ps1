#Requires -Version 7.0
#!/usr/bin/env pwsh
# Stop hook -- remind Claude to update install.* when files in hooks/, mcp/, statusline/, or sources.json are edited

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data -or $data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$lines = Get-Content $transcriptPath -Encoding utf8 -ErrorAction SilentlyContinue
if (-not $lines) { exit 0 }

# Find last REAL user prompt — only scan tool calls after it (current turn).
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

# Extract edited paths from Write/Edit/MultiEdit tool_use entries (JSON-parsed)
$paths = @()
for ($i = $lastUserIdx + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch '"name"\s*:\s*"(Write|Edit|MultiEdit)"') { continue }
    $rec = $null
    try { $rec = $lines[$i] | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    $content = $rec.message?.content
    if ($content -is [System.Array]) {
        foreach ($c in $content) {
            if ($c.type -eq 'tool_use' -and @('Write','Edit','MultiEdit') -contains $c.name -and $c.input?.file_path) {
                $paths += [string]$c.input.file_path
            }
        }
    }
}
if ($paths.Count -eq 0) { exit 0 }

$workDir = if ($data.cwd -and (Test-Path $data.cwd)) { $data.cwd } else { Get-Location }
$gitRoot = git -C $workDir rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitRoot) { exit 0 }
$gitRoot = $gitRoot.Trim()
$rootNorm = $gitRoot.Replace('\', '/').TrimEnd('/')

$needsHooks = $false
$needsMcp = $false
$needsStatusline = $false
$needsRoot = $false

foreach ($p in $paths) {
    $absNorm = $p.Replace('\', '/')
    if (-not $absNorm.StartsWith("$rootNorm/", [StringComparison]::OrdinalIgnoreCase)) { continue }
    $rel = $absNorm.Substring($rootNorm.Length + 1)

    if ($rel -match '^hooks/install\.(ps1|sh)$')           { continue }
    if ($rel -match '^mcp/install\.(ps1|sh)$')             { continue }
    if ($rel -match '^statusline/install\.(ps1|sh)$')      { continue }
    if ($rel -match '^install\.(ps1|sh)$')                 { continue }

    if ($rel -match '^hooks/')      { $needsHooks = $true;      continue }
    if ($rel -match '^mcp/')        { $needsMcp = $true;        continue }
    if ($rel -match '^statusline/') { $needsStatusline = $true; continue }
    if ($rel -eq    'sources.json') { $needsRoot = $true;       continue }
}

if (-not ($needsHooks -or $needsMcp -or $needsStatusline -or $needsRoot)) { exit 0 }

$msg = @("You modified files that affect cross-machine sync. Verify the installers are up to date:")
if ($needsHooks)      { $msg += "  - hooks/install.ps1 + hooks/install.sh (new/renamed hook scripts)" }
if ($needsMcp)        { $msg += "  - mcp/install.ps1 + mcp/install.sh (new MCP servers)" }
if ($needsStatusline) { $msg += "  - statusline/install.ps1 + statusline/install.sh (statusline changes)" }
if ($needsRoot)       { $msg += "  - root install.ps1 + install.sh (sources.json modified)" }
$msg += "Update them if needed so the sync does not break."

[Console]::Error.WriteLine(($msg -join "`n"))
exit 2
