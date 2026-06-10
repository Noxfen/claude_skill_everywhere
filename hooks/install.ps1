#Requires -Version 7.0
# claude_skill_everywhere -- hook installer (PowerShell 7+)
# Registers: update-docs-reminder (Stop), run-tests-on-stop (Stop),
#            auto-sync (SessionStart), lint-on-edit (PostToolUse)
#
# Usage (remote):  irm https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/hooks/install.ps1 | iex
# Usage (local):   pwsh -File hooks\install.ps1 [-Force]

param([switch]$Force)
$ErrorActionPreference = "Stop"

$RepoOwner = "Noxfen"
$RepoName  = "claude_skill_everywhere"
$RawBase   = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main"

$ClaudeDir = $env:CLAUDE_CONFIG_DIR ?? (Join-Path $env:USERPROFILE ".claude")
$HooksDir  = Join-Path $ClaudeDir "hooks"
$Settings  = Join-Path $ClaudeDir "settings.json"

if (-not (Test-Path $Settings)) {
    Write-Host "ERROR: $Settings not found." -ForegroundColor Red; exit 1
}

New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null

function Get-HookFile([string]$name) {
    $dest = Join-Path $HooksDir $name
    $local = $PSScriptRoot ? (Join-Path $PSScriptRoot $name) : $null
    if ($local -and (Test-Path $local)) {
        Copy-Item $local $dest -Force
    } else {
        Invoke-WebRequest "$RawBase/hooks/$name" -OutFile $dest
    }
    Write-Host "[+] Installed: $name" -ForegroundColor Green
}

Get-HookFile "update-docs-reminder.ps1"
Get-HookFile "run-tests-on-stop.ps1"
Get-HookFile "compact-warning.ps1"
Get-HookFile "track-context.ps1"
Get-HookFile "auto-sync.ps1"
Get-HookFile "lint-on-edit.ps1"
Get-HookFile "branch-context-injector.ps1"
Get-HookFile "unsafe-rust-blocker.ps1"
Get-HookFile "dep-audit.ps1"
Get-HookFile "installer-sync-reminder.ps1"

$json = Get-Content $Settings -Raw | ConvertFrom-Json
$json.hooks ??= [PSCustomObject]@{}

function Add-Hook([string]$eventName, [string]$command) {
    $entry = [PSCustomObject]@{ hooks = @([PSCustomObject]@{ type = "command"; command = $command }) }
    if (-not ($json.hooks.PSObject.Properties.Name -contains $eventName)) {
        $json.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue @() -Force
    }
    $basename = Split-Path $command.Trim('"') -Leaf
    $already = @($json.hooks.$eventName) | Where-Object {
        $_.hooks | Where-Object { $_.command -like "*$basename*" }
    }
    if ($already -and -not $Force) {
        Write-Host "[=] Hook already registered: $eventName ($basename)" -ForegroundColor Yellow
        return
    }
    if ($already) {
        # -Force: replace the existing entry instead of appending a duplicate
        $json.hooks.$eventName = @($json.hooks.$eventName | Where-Object {
            -not ($_.hooks | Where-Object { $_.command -like "*$basename*" })
        })
    }
    $json.hooks.$eventName = @($json.hooks.$eventName) + @($entry)
    Write-Host "[+] Registered hook: $eventName -> $basename" -ForegroundColor Green
}

$pwsh = (Get-Command pwsh).Source

Add-Hook "Stop"              "pwsh -NoProfile -File `"$HooksDir\update-docs-reminder.ps1`""
Add-Hook "Stop"              "pwsh -NoProfile -File `"$HooksDir\run-tests-on-stop.ps1`""
Add-Hook "Stop"              "pwsh -NoProfile -File `"$HooksDir\compact-warning.ps1`""
Add-Hook "Stop"              "pwsh -NoProfile -File `"$HooksDir\installer-sync-reminder.ps1`""
Add-Hook "SessionStart"      "pwsh -NoProfile -File `"$HooksDir\auto-sync.ps1`""
Add-Hook "PostToolUse"       "pwsh -NoProfile -File `"$HooksDir\lint-on-edit.ps1`""
Add-Hook "PostToolUse"       "pwsh -NoProfile -File `"$HooksDir\track-context.ps1`""
Add-Hook "PostToolUse"       "pwsh -NoProfile -File `"$HooksDir\dep-audit.ps1`""
Add-Hook "PreToolUse"        "pwsh -NoProfile -File `"$HooksDir\unsafe-rust-blocker.ps1`""
Add-Hook "UserPromptSubmit"  "pwsh -NoProfile -File `"$HooksDir\branch-context-injector.ps1`""

$json | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding utf8
Write-Host ""
Write-Host "Hooks installed. Restart Claude Code to activate." -ForegroundColor Cyan
