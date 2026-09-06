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

# Track failures so the final exit code is honest.
$Failures = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path $Settings)) {
    Write-Host "[+] $Settings not found -- creating a minimal one" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null
    Set-Content $Settings '{}' -Encoding utf8
}

$json = Get-Content $Settings -Raw | ConvertFrom-Json
if ($null -eq $json) { $json = [PSCustomObject]@{} }

# NB: `$json.prop ??= ...` cannot CREATE a property on a PSCustomObject --
# it throws "The property ... cannot be found" when the key is absent
# (e.g. a fresh `{}` settings file). Add-Member is required.
if (-not ($json.PSObject.Properties.Name -contains 'extraKnownMarketplaces')) {
    $json | Add-Member -NotePropertyName extraKnownMarketplaces -NotePropertyValue ([PSCustomObject]@{})
}

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
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $MarketDir)) {
        $Failures.Add("git clone marketplace repo (exit $LASTEXITCODE)")
        Write-Host "[!] Marketplace clone failed" -ForegroundColor Yellow
    }
} else {
    Write-Host "[=] Updating marketplace repo..." -ForegroundColor Yellow
    git -C $MarketDir pull --ff-only --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "[!] Marketplace pull failed (exit $LASTEXITCODE)" -ForegroundColor Yellow }
}

# Register only a clone that actually exists.
if ((Test-Path $KnownMarkets) -and (Test-Path $MarketDir)) {
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

# Sub-installers: run local copy or download; propagate real exit codes.
function Invoke-SubInstaller([string]$label, [string]$localRel, [string]$remoteRel, [string[]]$extraArgs = @()) {
    $local = $PSScriptRoot ? (Join-Path $PSScriptRoot $localRel) : $null
    try {
        if ($local -and (Test-Path $local)) {
            pwsh -NoProfile -File $local @extraArgs
        } else {
            $tmp = Join-Path $env:TEMP "noxfen-$label-install.ps1"
            Invoke-WebRequest "$RawBase/$remoteRel" -OutFile $tmp
            pwsh -NoProfile -File $tmp @extraArgs
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
        if ($LASTEXITCODE -ne 0) {
            $script:Failures.Add("$label installer (exit $LASTEXITCODE)")
            Write-Host "[!] $label installer failed (exit $LASTEXITCODE)" -ForegroundColor Yellow
        }
    } catch {
        $script:Failures.Add("$label installer ($($_.Exception.Message))")
        Write-Host "[!] $label installer failed: $_" -ForegroundColor Yellow
    }
}

$forceArg = $Force ? @("-Force") : @()
Invoke-SubInstaller "statusline" "statusline\install.ps1" "statusline/install.ps1"
Invoke-SubInstaller "mcp"        "mcp\install.ps1"        "mcp/install.ps1"
Invoke-SubInstaller "hooks"      "hooks\install.ps1"      "hooks/install.ps1" $forceArg

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
        try {
            claude plugin install $pluginId 2>$null
            if ($LASTEXITCODE -ne 0) {
                $Failures.Add("plugin $pluginId (exit $LASTEXITCODE)")
                Write-Host "[!] Failed to install $pluginId (exit $LASTEXITCODE)" -ForegroundColor Yellow
            }
        }
        catch {
            $Failures.Add("plugin $pluginId ($($_.Exception.Message))")
            Write-Host "[!] Failed to install $pluginId`: $_" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[=] No recommended plugins in sources.json" -ForegroundColor DarkGray
}

Write-Host ""
if ($Failures.Count -gt 0) {
    Write-Host "Completed with $($Failures.Count) failure(s):" -ForegroundColor Yellow
    foreach ($f in $Failures) { Write-Host "  - $f" -ForegroundColor Yellow }
} else {
    Write-Host "Done!" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "Next steps in Claude Code:" -ForegroundColor Gray
Write-Host "  /plugin discover                          -> browse available plugins" -ForegroundColor Gray
Write-Host "  /plugin install noxfen-essentials@noxfen  -> install skills" -ForegroundColor Gray
Write-Host ""
Write-Host "To sync after updating sources.json, re-run this installer." -ForegroundColor Gray

exit ($Failures.Count -gt 0 ? 1 : 0)
