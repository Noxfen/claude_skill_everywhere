#Requires -Version 7.0
#!/usr/bin/env pwsh
# MCP server installer -- installs filesystem, git, fetch, github at user scope
#
# Usage: pwsh -File mcp\install.ps1

$ErrorActionPreference = "Stop"

Write-Host "[MCP] Installing MCP servers..." -ForegroundColor Cyan

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Node.js required. Install from https://nodejs.org" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "[*] uv not found, installing via pip..." -ForegroundColor Yellow
    pip install uv --quiet
}

$UserHome = $env:USERPROFILE
$DevDir   = $env:CLAUDE_SKILL_DEV_DIR ?? "D:\dev"

$Servers = @(
    @{ name = "filesystem"; cmd = "npx"; args = @("-y", "@modelcontextprotocol/server-filesystem", $UserHome, $DevDir) }
    @{ name = "git";        cmd = "uvx"; args = @("mcp-server-git") }
    @{ name = "fetch";      cmd = "uvx"; args = @("mcp-server-fetch") }
    @{ name = "github";     cmd = "npx"; args = @("-y", "@modelcontextprotocol/server-github") }
)

$claudeJson = Join-Path $env:USERPROFILE ".claude.json"
$existingMcp = (Test-Path $claudeJson) ? ((Get-Content $claudeJson | ConvertFrom-Json).mcpServers?.PSObject.Properties.Name ?? @()) : @()

foreach ($s in $Servers) {
    if ($existingMcp -contains $s.name) {
        Write-Host "[=] Already configured: $($s.name)" -ForegroundColor Yellow
    } else {
        claude mcp add --scope user $s.name -- $s.cmd @($s.args) 2>$null
        Write-Host "[+] $($s.name): $($s.cmd) $($s.args -join ' ')" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Done. Restart Claude Code to activate MCP servers." -ForegroundColor Cyan
Write-Host "GitHub MCP needs GITHUB_TOKEN env var set." -ForegroundColor Yellow
