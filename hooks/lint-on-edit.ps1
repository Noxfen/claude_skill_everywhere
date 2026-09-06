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

# NB: the parameter must NOT be named $args -- that collides with the
# automatic $args variable and every call would receive ZERO arguments.
function Run-Format([string]$cmd, [string[]]$commandArgs) {
    if (-not (Has-Command $cmd)) { return }
    & $cmd @commandArgs 2>$null
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
    { $_ -in @("js","mjs","cjs","ts","tsx","jsx","svelte") } {
        $root = git -C (Split-Path $file -Parent) rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $root) {
            $hasPrettier = @(".prettierrc",".prettierrc.json",".prettierrc.yaml",".prettierrc.yml","prettier.config.js","prettier.config.mjs","prettier.config.ts") |
                Where-Object { Test-Path (Join-Path $root $_) } | Select-Object -First 1
            $hasEslint   = @("eslint.config.js","eslint.config.mjs","eslint.config.ts",".eslintrc.js",".eslintrc.cjs",".eslintrc.json") |
                Where-Object { Test-Path (Join-Path $root $_) } | Select-Object -First 1
            # Prefer the project's own binaries over globals -- most projects
            # install formatters only in node_modules/.bin.
            $localPrettier = Join-Path $root "node_modules\.bin\prettier.cmd"
            $localEslint   = Join-Path $root "node_modules\.bin\eslint.cmd"
            if ($hasPrettier) {
                if (Test-Path $localPrettier) { Run-Format $localPrettier @("--write", $file) }
                else                          { Run-Format "prettier"     @("--write", $file) }
            }
            if ($hasEslint) {
                if (Test-Path $localEslint) { Run-Format $localEslint @("--fix", "--quiet", $file) }
                else                        { Run-Format "eslint"     @("--fix", "--quiet", $file) }
            }
        }
    }
    { $_ -in @("c","h","cpp","hpp","cc","cxx") } { Run-Format "clang-format" @("-i", $file) }
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
        } catch { }
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
