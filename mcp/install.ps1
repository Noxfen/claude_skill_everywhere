# MCP server installer (Windows)
# Installs: filesystem, git, fetch, github at user scope
#
# Usage: powershell -ExecutionPolicy Bypass -File mcp\install.ps1

$ErrorActionPreference = "Stop"

Write-Host "[MCP] Installing MCP servers..." -ForegroundColor Cyan

# Check Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Node.js required. Install from https://nodejs.org" -ForegroundColor Red
    exit 1
}

# Check/install uv
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "[*] uv not found, installing via pip..." -ForegroundColor Yellow
    pip install uv --quiet
}

$UserHome = $env:USERPROFILE
$DevDir   = "D:\dev"

$Servers = @(
    @{ name = "filesystem"; cmd = "npx"; args = @("-y", "@modelcontextprotocol/server-filesystem", $UserHome, $DevDir) },
    @{ name = "git";        cmd = "uvx"; args = @("mcp-server-git") },
    @{ name = "fetch";      cmd = "uvx"; args = @("mcp-server-fetch") },
    @{ name = "github";     cmd = "npx"; args = @("-y", "@modelcontextprotocol/server-github") }
)

$claudeJson = Join-Path $env:USERPROFILE ".claude.json"
$existingMcp = @()
if (Test-Path $claudeJson) {
    try {
        $existingMcp = (Get-Content $claudeJson -Raw | ConvertFrom-Json).mcpServers.PSObject.Properties.Name
    } catch { }
}

foreach ($s in $Servers) {
    $argsStr = $s.args -join " "
    if ($existingMcp -contains $s.name) {
        Write-Host "[=] Already configured: $($s.name)" -ForegroundColor Yellow
    } else {
        & claude mcp add --scope user $s.name -- $s.cmd @($s.args) 2>$null
        Write-Host "[+] $($s.name): $($s.cmd) $argsStr" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Done. Restart Claude Code to activate MCP servers." -ForegroundColor Cyan
Write-Host "GitHub MCP needs GITHUB_TOKEN env var set." -ForegroundColor Yellow
