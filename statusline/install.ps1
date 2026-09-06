#Requires -Version 7.0
#!/usr/bin/env pwsh
# Statusline installer (Windows) -- deploys statusline script and patches settings.json
#
# Usage: pwsh -File statusline\install.ps1

$ErrorActionPreference = "Stop"

$RawBase  = "https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main"
$ClaudeDir = $env:CLAUDE_CONFIG_DIR ?? (Join-Path $env:USERPROFILE ".claude")
$Settings  = Join-Path $ClaudeDir "settings.json"
$DestScript = Join-Path $ClaudeDir "statusline-command.ps1"

if (-not (Test-Path $Settings)) {
    Write-Host "ERROR: $Settings not found." -ForegroundColor Red; exit 1
}

# Deploy script
$local = $PSScriptRoot ? (Join-Path $PSScriptRoot "statusline-command.ps1") : $null
if ($local -and (Test-Path $local)) {
    Copy-Item $local $DestScript -Force
} else {
    Invoke-WebRequest "$RawBase/statusline/statusline-command.ps1" -OutFile $DestScript
}
Write-Host "[+] Deployed statusline-command.ps1" -ForegroundColor Green

# Patch settings.json
$json = Get-Content $Settings -Raw | ConvertFrom-Json
if ($null -eq $json) { $json = [PSCustomObject]@{} }
$cmd  = "pwsh -NoProfile -File `"$DestScript`""

# NB: `??=` cannot CREATE a property on a PSCustomObject -- it throws when
# the key is absent (fresh `{}` settings). Add-Member is required.
if (-not ($json.PSObject.Properties.Name -contains 'statusLine')) {
    $json | Add-Member -NotePropertyName statusLine -NotePropertyValue ([PSCustomObject]@{})
}
$json.statusLine | Add-Member -NotePropertyName "type"    -NotePropertyValue "command" -Force
$json.statusLine | Add-Member -NotePropertyName "command" -NotePropertyValue $cmd      -Force
# Set a default refresh only when the user has not chosen one.
if (-not ($json.statusLine.PSObject.Properties.Name -contains 'refreshInterval')) {
    $json.statusLine | Add-Member -NotePropertyName "refreshInterval" -NotePropertyValue 60
}

$json | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding utf8
Write-Host "[+] settings.json updated (statusLine -> pwsh)" -ForegroundColor Green
