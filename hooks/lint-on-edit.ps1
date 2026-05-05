#!/usr/bin/env pwsh
# PostToolUse hook — auto-format/lint file after Write or Edit (Windows)
# Detects language from extension, runs appropriate tool if available.
# Silent on missing tools. Always exits 0 (informational only, never blocks).

$json = [Console]::In.ReadToEnd()
try { $data = $json | ConvertFrom-Json } catch { exit 0 }

$tool = $data.tool_name
if ($tool -ne "Write" -and $tool -ne "Edit") { exit 0 }

$file = $data.tool_input?.file_path
if (-not $file -or -not (Test-Path $file)) { exit 0 }

$ext = [System.IO.Path]::GetExtension($file).TrimStart('.').ToLower()

function Has-Command($cmd) {
    return (Get-Command $cmd -ErrorAction SilentlyContinue) -ne $null
}

function Run-Format($cmd, $args) {
    if (-not (Has-Command $cmd)) { return }
    try {
        & $cmd @args 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Output "[lint] formatted: $file" }
    } catch { }
}

switch ($ext) {
    "rs" {
        Run-Format "rustfmt" @($file)
        # Try clippy from cargo workspace
        $dir = Split-Path $file -Parent
        try {
            $cargoToml = & cargo locate-project --manifest-path (Join-Path $dir "Cargo.toml") --message-format plain 2>$null
            if ($cargoToml) {
                $workspace = Split-Path $cargoToml -Parent
                & cargo clippy --manifest-path (Join-Path $workspace "Cargo.toml") --quiet 2>$null
            }
        } catch { }
    }
    "py" {
        Run-Format "ruff" @("format", $file)
        if (Has-Command "ruff") {
            & ruff check --fix --quiet $file 2>$null
        }
    }
    { $_ -in @("js","mjs","cjs","ts","tsx","jsx") } {
        $projRoot = & git -C (Split-Path $file -Parent) rev-parse --show-toplevel 2>$null
        if ($projRoot -and (Test-Path $projRoot)) {
            $hasPrettier = (Test-Path (Join-Path $projRoot ".prettierrc")) -or
                           (Test-Path (Join-Path $projRoot "prettier.config.js")) -or
                           (Test-Path (Join-Path $projRoot "prettier.config.ts"))
            if ($hasPrettier) { Run-Format "prettier" @("--write", $file) }

            $hasEslint  = (Test-Path (Join-Path $projRoot "eslint.config.js")) -or
                          (Test-Path (Join-Path $projRoot ".eslintrc.js")) -or
                          (Test-Path (Join-Path $projRoot ".eslintrc.json"))
            if ($hasEslint) { Run-Format "eslint" @("--fix", "--quiet", $file) }
        }
    }
    { $_ -in @("c","h","cpp","hpp","cc","cxx") } {
        Run-Format "clang-format" @("-i", $file)
    }
    { $_ -in @("ps1","psm1","psd1") } {
        try {
            Import-Module PSScriptAnalyzer -ErrorAction Stop
            $results = Invoke-ScriptAnalyzer -Path $file -Severity @("Warning","Error") -ErrorAction Stop
            if ($results) {
                Write-Output "[lint] PSScriptAnalyzer $file :"
                $results | ForEach-Object { Write-Output "  [$($_.Severity)] $($_.RuleName) L$($_.Line): $($_.Message)" }
            } else {
                Write-Output "[lint] PSScriptAnalyzer OK: $file"
            }
        } catch {
            # PSScriptAnalyzer not installed -- silent
        }
    }
    { $_ -in @("sh","bash") } {
        if (Has-Command "shellcheck") {
            $out = & shellcheck -S warning $file 2>&1
            if ($out) {
                Write-Output "[lint] shellcheck $file :"
                $out | ForEach-Object { Write-Output "  $_" }
            } else {
                Write-Output "[lint] shellcheck OK: $file"
            }
        }
    }
}

exit 0
