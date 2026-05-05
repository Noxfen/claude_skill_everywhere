#Requires -Version 7.0
#!/usr/bin/env pwsh
# PostToolUse hook -- auto-format/lint after Write or Edit
# Silent on missing tools. Always exits 0 (never blocks Claude).

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data) { exit 0 }

if ($data.tool_name -notin @("Write", "Edit")) { exit 0 }

$file = $data.tool_input?.file_path
if (-not $file -or -not (Test-Path $file)) { exit 0 }

$ext = [System.IO.Path]::GetExtension($file).TrimStart('.').ToLower()

function Has-Command([string]$cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Run-Format([string]$cmd, [string[]]$args) {
    if (-not (Has-Command $cmd)) { return }
    & $cmd @args 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Output "[lint] formatted: $file" }
}

switch ($ext) {
    "rs" {
        Run-Format "rustfmt" @($file)
        $dir = Split-Path $file -Parent
        $toml = git -C $dir rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $toml -and (Test-Path (Join-Path $toml "Cargo.toml"))) {
            cargo clippy --manifest-path (Join-Path $toml "Cargo.toml") --quiet 2>$null
        }
    }
    "py" {
        Run-Format "ruff" @("format", $file)
        if (Has-Command "ruff") { ruff check --fix --quiet $file 2>$null }
    }
    { $_ -in @("js","mjs","cjs","ts","tsx","jsx") } {
        $root = git -C (Split-Path $file -Parent) rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $root) {
            $hasPrettier = (Test-Path "$root/.prettierrc") -or (Test-Path "$root/prettier.config.js") -or (Test-Path "$root/prettier.config.ts")
            $hasEslint   = (Test-Path "$root/eslint.config.js") -or (Test-Path "$root/.eslintrc.js") -or (Test-Path "$root/.eslintrc.json")
            if ($hasPrettier) { Run-Format "prettier" @("--write", $file) }
            if ($hasEslint)   { Run-Format "eslint"   @("--fix", "--quiet", $file) }
        }
    }
    { $_ -in @("c","h","cpp","hpp","cc","cxx") } { Run-Format "clang-format" @("-i", $file) }
    { $_ -in @("ps1","psm1","psd1") } {
        if (Has-Command "pwsh") {
            $results = pwsh -NoProfile -Command "Import-Module PSScriptAnalyzer -EA Stop; Invoke-ScriptAnalyzer -Path '$file' -Severity Warning,Error | ForEach-Object { `"  [`$(`$_.Severity)] `$(`$_.RuleName) L`$(`$_.Line): `$(`$_.Message)`" }" 2>$null
            if ($results) {
                Write-Output "[lint] PSScriptAnalyzer $file :"
                $results | Write-Output
            } else {
                Write-Output "[lint] PSScriptAnalyzer OK: $file"
            }
        }
    }
    { $_ -in @("sh","bash") } {
        if (Has-Command "shellcheck") {
            $out = shellcheck -S warning $file 2>&1
            $label = $out ? "[lint] shellcheck $file :" : "[lint] shellcheck OK: $file"
            Write-Output $label
            if ($out) { $out | Write-Output }
        }
    }
}

exit 0
