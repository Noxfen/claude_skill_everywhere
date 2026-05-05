# claude_skill_everywhere — Windows/PowerShell installer
# Registers this marketplace + all external marketplaces from sources.json
# into ~/.claude/settings.json
#
# Usage (remote):
#   irm https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.ps1 | iex
# Usage (local clone):
#   powershell -ExecutionPolicy Bypass -File install.ps1

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$RepoOwner  = "Noxfen"
$RepoName   = "claude_skill_everywhere"
$MarketKey  = "noxfen"
$RawBase    = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main"

$ClaudeDir  = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }
$Settings   = Join-Path $ClaudeDir "settings.json"

Write-Host ""
Write-Host "claude_skill_everywhere installer" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# --- Load settings.json ---
if (-not (Test-Path $Settings)) {
    Write-Host "ERROR: $Settings not found. Is Claude Code installed?" -ForegroundColor Red
    exit 1
}

$json = Get-Content $Settings -Raw | ConvertFrom-Json

# Ensure extraKnownMarketplaces exists
if (-not ($json.PSObject.Properties.Name -contains "extraKnownMarketplaces")) {
    $json | Add-Member -NotePropertyName "extraKnownMarketplaces" -NotePropertyValue ([PSCustomObject]@{})
}

# --- Register this repo as a marketplace ---
$thisSource = [PSCustomObject]@{
    source = [PSCustomObject]@{
        source = "github"
        repo   = "$RepoOwner/$RepoName"
    }
}

if (-not ($json.extraKnownMarketplaces.PSObject.Properties.Name -contains $MarketKey) -or $Force) {
    $json.extraKnownMarketplaces | Add-Member -NotePropertyName $MarketKey -NotePropertyValue $thisSource -Force
    Write-Host "[+] Registered marketplace: $MarketKey ($RepoOwner/$RepoName)" -ForegroundColor Green
} else {
    Write-Host "[=] Marketplace already registered: $MarketKey" -ForegroundColor Yellow
}

# --- Load sources.json and register external marketplaces ---
$sourcesJson = $null

# Try local file first (if running from a clone)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $null }
$localSources = if ($ScriptDir) { Join-Path $ScriptDir "sources.json" } else { $null }

if ($localSources -and (Test-Path $localSources)) {
    $sourcesJson = Get-Content $localSources -Raw | ConvertFrom-Json
} else {
    try {
        $raw = Invoke-RestMethod "$RawBase/sources.json"
        $sourcesJson = $raw
    } catch {
        Write-Host "[!] Could not fetch sources.json — skipping external marketplaces" -ForegroundColor Yellow
    }
}

if ($sourcesJson -and $sourcesJson.external_marketplaces) {
    foreach ($ext in $sourcesJson.external_marketplaces) {
        $extKey = $ext.name
        $extRepo = $ext.repo
        if (-not ($json.extraKnownMarketplaces.PSObject.Properties.Name -contains $extKey) -or $Force) {
            $extSource = [PSCustomObject]@{
                source = [PSCustomObject]@{
                    source = "github"
                    repo   = $extRepo
                }
            }
            $json.extraKnownMarketplaces | Add-Member -NotePropertyName $extKey -NotePropertyValue $extSource -Force
            Write-Host "[+] Registered external marketplace: $extKey ($extRepo)" -ForegroundColor Green
        } else {
            Write-Host "[=] Already registered: $extKey" -ForegroundColor Yellow
        }
    }
}

# --- Write settings.json back ---
$json | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding utf8
Write-Host ""
Write-Host "Done!" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps in Claude Code:" -ForegroundColor White
Write-Host "  /plugin discover               -> browse available plugins" -ForegroundColor Gray
Write-Host "  /plugin install noxfen-essentials@noxfen  -> install skills" -ForegroundColor Gray
Write-Host ""
Write-Host "To sync after updating sources.json, re-run this installer." -ForegroundColor Gray
