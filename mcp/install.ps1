#Requires -Version 7.0
#!/usr/bin/env pwsh
# MCP server installer -- installs filesystem, git, fetch, github, svelte (+ rea when installed) at user scope
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

# git/fetch pin the mcp SDK below 2.0: SDK 2.0.0 renamed McpError -> MCPError,
# which breaks mcp-server-fetch on import. Remove the pin once upstream
# mcp-server-fetch is compatible with mcp>=2.
$Servers = @(
    @{ name = "filesystem"; cmd = "npx"; args = @("-y", "@modelcontextprotocol/server-filesystem", $UserHome, $DevDir) }
    @{ name = "git";        cmd = "uvx"; args = @("--with", "mcp<2", "mcp-server-git") }
    @{ name = "fetch";      cmd = "uvx"; args = @("--with", "mcp<2", "mcp-server-fetch") }
    @{ name = "github";     cmd = "npx"; args = @("-y", "@modelcontextprotocol/server-github") }
)

$claudeJson = Join-Path $env:USERPROFILE ".claude.json"
$existingMcp = (Test-Path $claudeJson) ? ((Get-Content $claudeJson | ConvertFrom-Json).mcpServers?.PSObject.Properties.Name ?? @()) : @()

$failed = @()

foreach ($s in $Servers) {
    if ($existingMcp -contains $s.name) {
        Write-Host "[=] Already configured: $($s.name)" -ForegroundColor Yellow
    } else {
        claude mcp add --scope user $s.name -- $s.cmd @($s.args) 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] $($s.name): $($s.cmd) $($s.args -join ' ')" -ForegroundColor Green
        } else {
            $failed += $s.name
            Write-Host "[!] Failed to add $($s.name) (exit $LASTEXITCODE)" -ForegroundColor Yellow
        }
    }
}

# rea (reverse-engineering MCP, npm package rea-agents, MIT). Registered only
# when already installed -- the installer never runs third-party npm code.
# Native Windows install wins; otherwise use a WSL install (distro from
# CLAUDE_SKILL_REA_WSL_DISTRO, else the default WSL distro).
if ($existingMcp -contains "rea") {
    Write-Host "[=] Already configured: rea" -ForegroundColor Yellow
} else {
    $reaArgs = $null
    if (Get-Command rea -ErrorAction SilentlyContinue) {
        $reaCmd = "rea"; $reaArgs = @("mcp")
    } elseif (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        $distroArgs = $env:CLAUDE_SKILL_REA_WSL_DISTRO ? @("-d", $env:CLAUDE_SKILL_REA_WSL_DISTRO) : @()
        wsl.exe @distroArgs -- bash -lc "command -v rea" *> $null
        if ($LASTEXITCODE -eq 0) {
            $reaCmd = "wsl.exe"; $reaArgs = $distroArgs + @("--", "bash", "-lc", "exec rea mcp")
        }
    }
    if ($reaArgs) {
        claude mcp add --scope user rea -- $reaCmd @reaArgs 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] rea: $reaCmd $($reaArgs -join ' ')" -ForegroundColor Green
        } else {
            $failed += "rea"
            Write-Host "[!] Failed to add rea (exit $LASTEXITCODE)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[-] rea not installed (Windows or WSL) -- skipping (install: npm install -g rea-agents)" -ForegroundColor DarkGray
    }
}

# HTTP transport servers (no local process)
$HttpServers = @(
    @{ name = "svelte"; url = "https://mcp.svelte.dev/mcp"; desc = "Official Svelte/SvelteKit MCP" }
)

foreach ($s in $HttpServers) {
    if ($existingMcp -contains $s.name) {
        Write-Host "[=] Already configured: $($s.name)" -ForegroundColor Yellow
    } else {
        claude mcp add --scope user --transport http $s.name $s.url 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] $($s.name) (http): $($s.url)" -ForegroundColor Green
        } else {
            $failed += $s.name
            Write-Host "[!] Failed to add $($s.name) (exit $LASTEXITCODE)" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "Completed with failures: $($failed -join ', ')" -ForegroundColor Yellow
} else {
    Write-Host "Done. Restart Claude Code to activate MCP servers." -ForegroundColor Cyan
}
Write-Host "GitHub MCP needs the GITHUB_PERSONAL_ACCESS_TOKEN env var set." -ForegroundColor Yellow

exit ($failed.Count -gt 0 ? 1 : 0)
