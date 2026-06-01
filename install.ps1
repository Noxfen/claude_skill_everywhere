#Requires -Version 7.0
# claude_skill_everywhere -- installer (PowerShell 7+)
# Registers marketplace, clones repo, installs MCP servers, hooks, and recommended plugins.
#
# Usage (remote):  irm https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/install.ps1 | iex
# Usage (local):   pwsh -File install.ps1 [-Force]

param([switch]$Force)
$ErrorActionPreference = "Stop"

$RepoOwner = "Noxfen"
$RepoName  = "claude_skill_everywhere"
$MarketKey = "noxfen"
$RawBase   = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main"

$ClaudeDir = $env:CLAUDE_CONFIG_DIR ?? (Join-Path $env:USERPROFILE ".claude")
$Settings  = Join-Path $ClaudeDir "settings.json"

Write-Host ""
Write-Host "claude_skill_everywhere installer" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $Settings)) {
    Write-Host "ERROR: $Settings not found. Is Claude Code installed?" -ForegroundColor Red
    exit 1
}

$json = Get-Content $Settings -Raw | ConvertFrom-Json

$json.extraKnownMarketplaces ??= [PSCustomObject]@{}

# Register this repo as marketplace
$thisSource = [PSCustomObject]@{ source = [PSCustomObject]@{ source = "github"; repo = "$RepoOwner/$RepoName" } }
if (-not ($json.extraKnownMarketplaces.PSObject.Properties.Name -contains $MarketKey) -or $Force) {
    $json.extraKnownMarketplaces | Add-Member -NotePropertyName $MarketKey -NotePropertyValue $thisSource -Force
    Write-Host "[+] Registered marketplace: $MarketKey ($RepoOwner/$RepoName)" -ForegroundColor Green
} else {
    Write-Host "[=] Marketplace already registered: $MarketKey" -ForegroundColor Yellow
}

# Load sources.json (local copy preferred, else fetch from RawBase)
$sourcesJson = $null
$localSources = $PSScriptRoot ? (Join-Path $PSScriptRoot "sources.json") : $null
if ($localSources -and (Test-Path $localSources)) {
    try { $sourcesJson = Get-Content $localSources -Raw | ConvertFrom-Json }
    catch { Write-Host "[!] Failed to parse $localSources`: $_" -ForegroundColor Yellow }
} else {
    try { $sourcesJson = Invoke-RestMethod "$RawBase/sources.json" }
    catch { Write-Host "[!] Could not fetch sources.json -- skipping external marketplaces & plugins" -ForegroundColor Yellow }
}
if ($sourcesJson) {
    Write-Host "[=] Loaded sources.json ($($sourcesJson.external_marketplaces.Count) marketplace(s), $($sourcesJson.recommended_plugins.Count) plugin(s))" -ForegroundColor DarkGray
} else {
    Write-Host "[!] sources.json not loaded -- external marketplaces & recommended plugins will be skipped" -ForegroundColor Yellow
}

# Register external marketplaces
# NOTE: must be ($sourcesJson -and $sourcesJson.x), NOT ($sourcesJson?.x).
# PowerShell allows '?' in variable names, so unbraced `$sourcesJson?.x` parses
# as variable ${sourcesJson?} (nonexistent -> $null) and silently skips the block.
if ($sourcesJson -and $sourcesJson.external_marketplaces) {
    foreach ($ext in $sourcesJson.external_marketplaces) {
        $extSource = [PSCustomObject]@{ source = [PSCustomObject]@{ source = "github"; repo = $ext.repo } }
        if (-not ($json.extraKnownMarketplaces.PSObject.Properties.Name -contains $ext.name) -or $Force) {
            $json.extraKnownMarketplaces | Add-Member -NotePropertyName $ext.name -NotePropertyValue $extSource -Force
            Write-Host "[+] Registered external marketplace: $($ext.name) ($($ext.repo))" -ForegroundColor Green
        } else {
            Write-Host "[=] Already registered: $($ext.name)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[=] No external marketplaces in sources.json" -ForegroundColor DarkGray
}

# Write settings.json (PS7 Set-Content uses UTF-8 without BOM by default)
$json | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding utf8

# Clone/update marketplace repo + register in known_marketplaces.json
$PluginsDir   = Join-Path $ClaudeDir "plugins"
$MarketDir    = Join-Path $PluginsDir "marketplaces\Noxfen-claude_skill_everywhere"
$KnownMarkets = Join-Path $PluginsDir "known_marketplaces.json"

if (-not (Test-Path $MarketDir)) {
    Write-Host "[+] Cloning marketplace repo..." -ForegroundColor Green
    git clone "https://github.com/$RepoOwner/$RepoName.git" $MarketDir 2>$null
} else {
    Write-Host "[=] Updating marketplace repo..." -ForegroundColor Yellow
    git -C $MarketDir pull --ff-only --quiet 2>$null
}

if (Test-Path $KnownMarkets) {
    $km = Get-Content $KnownMarkets -Raw | ConvertFrom-Json
    if (-not ($km.PSObject.Properties.Name -contains $MarketKey) -or $Force) {
        $km | Add-Member -NotePropertyName $MarketKey -NotePropertyValue ([PSCustomObject]@{
            source          = [PSCustomObject]@{ source = "github"; repo = "$RepoOwner/$RepoName" }
            installLocation = $MarketDir
            lastUpdated     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
        }) -Force
        $km | ConvertTo-Json -Depth 10 | Set-Content $KnownMarkets -Encoding utf8
        Write-Host "[+] Registered in known_marketplaces.json" -ForegroundColor Green
    }
}

# Install statusline
$statuslineInstaller = $PSScriptRoot ? (Join-Path $PSScriptRoot "statusline\install.ps1") : $null
try {
    if ($statuslineInstaller -and (Test-Path $statuslineInstaller)) {
        pwsh -NoProfile -File $statuslineInstaller
    } else {
        $tmp = Join-Path $env:TEMP "noxfen-statusline-install.ps1"
        Invoke-WebRequest "$RawBase/statusline/install.ps1" -OutFile $tmp
        pwsh -NoProfile -File $tmp
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
} catch { Write-Host "[!] Statusline installer failed: $_" -ForegroundColor Yellow }

# Install MCP servers
$mcpInstaller = $PSScriptRoot ? (Join-Path $PSScriptRoot "mcp\install.ps1") : $null
try {
    if ($mcpInstaller -and (Test-Path $mcpInstaller)) {
        pwsh -NoProfile -File $mcpInstaller
    } else {
        $tmp = Join-Path $env:TEMP "noxfen-mcp-install.ps1"
        Invoke-WebRequest "$RawBase/mcp/install.ps1" -OutFile $tmp
        pwsh -NoProfile -File $tmp
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
} catch { Write-Host "[!] MCP installer failed: $_" -ForegroundColor Yellow }

# Install hooks
$hooksInstaller = $PSScriptRoot ? (Join-Path $PSScriptRoot "hooks\install.ps1") : $null
try {
    if ($hooksInstaller -and (Test-Path $hooksInstaller)) {
        $forceArg = $Force ? @("-Force") : @()
        pwsh -NoProfile -File $hooksInstaller @forceArg
    } else {
        $tmp = Join-Path $env:TEMP "noxfen-hooks-install.ps1"
        Invoke-WebRequest "$RawBase/hooks/install.ps1" -OutFile $tmp
        pwsh -NoProfile -File $tmp
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
} catch { Write-Host "[!] Hook installer failed: $_" -ForegroundColor Yellow }

# Install recommended plugins
# NOTE: ($sourcesJson -and ...), NOT ($sourcesJson?.x) -- see external marketplaces note above.
if ($sourcesJson -and $sourcesJson.recommended_plugins) {
    Write-Host ""
    Write-Host "Installing recommended plugins..." -ForegroundColor Cyan
    foreach ($p in $sourcesJson.recommended_plugins) {
        $pluginId = "$($p.name)@$($p.marketplace)"
        Write-Host "[+] Installing $pluginId..." -ForegroundColor Green
        # try/catch so one failing install can't abort the loop under
        # $PSNativeCommandUseErrorActionPreference + $ErrorActionPreference='Stop'.
        try { claude plugin install $pluginId 2>$null }
        catch { Write-Host "[!] Failed to install $pluginId`: $_" -ForegroundColor Yellow }
    }
} else {
    Write-Host "[=] No recommended plugins in sources.json" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Cyan
Write-Host ""
Write-Host "To sync after updating sources.json, re-run this installer." -ForegroundColor Gray
