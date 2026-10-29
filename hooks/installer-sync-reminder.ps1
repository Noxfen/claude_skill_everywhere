#Requires -Version 7.0
#!/usr/bin/env pwsh
# Stop hook -- remind Claude to update install.* when files in hooks/, mcp/, statusline/, or sources.json are edited

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data -or $data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$lines = @(Get-Content $transcriptPath -Encoding utf8 -ErrorAction SilentlyContinue)
if (-not $lines) { exit 0 }

# --- current-turn scan: keep IDENTICAL across the 3 Stop hooks (.ps1 + .sh) ---
# Anchor = last REAL user prompt: a "type":"user" record that is neither a
# tool_result carrier nor isMeta (Skill bodies, agent messages and Stop-hook
# feedback are injected mid-turn as isMeta user records). Edits = tool_use
# inside records whose top-level type is "assistant" only: other record types
# (e.g. api-request-blob) replay the WHOLE history. -AsHashtable because plain
# ConvertFrom-Json throws on valid JSON with keys differing only by case;
# comparisons are case-sensitive to match the Python half.
function ConvertFrom-JsonLine([string]$line) {
    try { return ($line | ConvertFrom-Json -AsHashtable -ErrorAction Stop) } catch { return $null }
}
function Get-MessageContent($rec) {
    $msg = $rec['message']
    # Leading comma: a function returning a 1-element array would otherwise
    # unroll it to the bare element and the IList checks below would fail.
    if ($msg -is [System.Collections.IDictionary]) { return ,$msg['content'] }
    return $null
}
$lastUserIdx = -1
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '"type"\s*:\s*"user"') { continue }
    $rec = ConvertFrom-JsonLine $lines[$i]
    if ($rec -isnot [System.Collections.IDictionary]) {
        if ($lines[$i] -notmatch '"tool_result"') { $lastUserIdx = $i; break }
        continue
    }
    if ($rec['type'] -cne 'user' -or $rec['isMeta'] -eq $true) { continue }
    $content = Get-MessageContent $rec
    $isToolResult = $false
    if ($content -is [System.Collections.IList]) {
        foreach ($c in $content) {
            if ($c -is [System.Collections.IDictionary] -and $c['type'] -ceq 'tool_result') { $isToolResult = $true; break }
        }
    }
    if (-not $isToolResult) { $lastUserIdx = $i; break }
}
$EditTools = @('Write', 'Edit', 'MultiEdit')
$editedPaths = [System.Collections.Generic.List[string]]::new()
$hasEdit = $false
for ($i = $lastUserIdx + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch '"name"\s*:\s*"(Write|Edit|MultiEdit)"') { continue }
    $rec = ConvertFrom-JsonLine $lines[$i]
    if ($rec -isnot [System.Collections.IDictionary] -or $rec['type'] -cne 'assistant') { continue }
    $content = Get-MessageContent $rec
    if ($content -isnot [System.Collections.IList]) { continue }
    foreach ($c in $content) {
        if ($c -is [System.Collections.IDictionary] -and $c['type'] -ceq 'tool_use' -and $EditTools -ccontains $c['name']) {
            $hasEdit = $true
            $inp = $c['input']
            if ($inp -is [System.Collections.IDictionary] -and $inp['file_path']) { $editedPaths.Add([string]$inp['file_path']) }
        }
    }
}
# --- end current-turn scan ---
$paths = @($editedPaths)
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
