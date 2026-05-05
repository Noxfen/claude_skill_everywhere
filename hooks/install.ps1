# claude_skill_everywhere -- hook installer (Windows/PowerShell)
# Registers update-docs-reminder (Stop), auto-sync (SessionStart),
# lint-on-edit (PostToolUse) into settings.json
#
# Usage (remote):
#   irm https://raw.githubusercontent.com/Noxfen/claude_skill_everywhere/main/hooks/install.ps1 | iex
# Usage (local):
#   powershell -ExecutionPolicy Bypass -File hooks\install.ps1 [-Force]

param([switch]$Force)
$ErrorActionPreference = "Stop"

$RepoOwner = "Noxfen"
$RepoName  = "claude_skill_everywhere"
$RawBase   = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main"

$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }
$HooksDir  = Join-Path $ClaudeDir "hooks"
$Settings  = Join-Path $ClaudeDir "settings.json"

if (-not (Test-Path $Settings)) {
    Write-Host "ERROR: $Settings not found." -ForegroundColor Red; exit 1
}

New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $null }

function Get-HookFile($name) {
    $dest = Join-Path $HooksDir $name
    if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir $name))) {
        Copy-Item (Join-Path $ScriptDir $name) $dest -Force
    } else {
        Invoke-WebRequest "$RawBase/hooks/$name" -OutFile $dest
    }
    Write-Host "[+] Installed hook script: $name" -ForegroundColor Green
}

Get-HookFile "update-docs-reminder.ps1"
Get-HookFile "auto-sync.ps1"
Get-HookFile "lint-on-edit.ps1"

$json = Get-Content $Settings -Raw | ConvertFrom-Json

if (-not ($json.PSObject.Properties.Name -contains "hooks")) {
    $json | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{})
}

function Add-Hook($eventName, $command) {
    $hookEntry = [PSCustomObject]@{
        hooks = @([PSCustomObject]@{ type = "command"; command = $command })
    }
    if (-not ($json.hooks.PSObject.Properties.Name -contains $eventName)) {
        $json.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue @() -Force
    }
    $existing = @($json.hooks.$eventName)
    $alreadyPresent = $existing | Where-Object {
        $_.hooks | Where-Object { $_.command -like "*$($command.Split('\')[-1])*" }
    }
    if (-not $alreadyPresent -or $Force) {
        $json.hooks.$eventName = @($existing) + @($hookEntry)
        Write-Host "[+] Registered hook: $eventName -> $command" -ForegroundColor Green
    } else {
        Write-Host "[=] Hook already registered: $eventName" -ForegroundColor Yellow
    }
}

$docsCmd = "powershell.exe -NoProfile -File `"$HooksDir\update-docs-reminder.ps1`""
$syncCmd = "powershell.exe -NoProfile -File `"$HooksDir\auto-sync.ps1`""
$lintCmd = "powershell.exe -NoProfile -File `"$HooksDir\lint-on-edit.ps1`""

Add-Hook "Stop"         $docsCmd
Add-Hook "SessionStart" $syncCmd
Add-Hook "PostToolUse"  $lintCmd

$jsonText = $json | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($Settings, $jsonText, (New-Object System.Text.UTF8Encoding $false))
Write-Host ""
Write-Host "Hooks installed. Restart Claude Code to activate." -ForegroundColor Cyan
