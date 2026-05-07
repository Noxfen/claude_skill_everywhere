#Requires -Version 7.0
#!/usr/bin/env pwsh
# PostToolUse hook -- run security audit when dependency files change.
# Cargo.toml -> cargo audit, package.json -> npm audit, pyproject.toml/requirements.txt -> pip-audit.
# Exit 2 + stderr injects vulnerability summary to Claude.

trap { exit 0 }

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data) { exit 0 }

$tool = $data.tool_name
if ($tool -notin @("Write", "Edit", "MultiEdit")) { exit 0 }

$path = $data.tool_input.file_path
if (-not $path) { exit 0 }

$file = Split-Path $path -Leaf
$dir  = Split-Path $path -Parent
if (-not (Test-Path $dir)) { exit 0 }

function Run-Audit([string]$cmd, [string[]]$cmdArgs, [string]$label) {
    $psi = [System.Diagnostics.ProcessStartInfo]@{
        FileName               = $cmd
        Arguments              = $cmdArgs -join " "
        WorkingDirectory       = $dir
        RedirectStandardOutput = $true
        RedirectStandardError  = $true
        UseShellExecute        = $false
        CreateNoWindow         = $true
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $finished = $proc.WaitForExit(45000)
    if (-not $finished) { $proc.Kill(); return }
    if ($proc.ExitCode -ne 0) {
        $output = "$stdout`n$stderr".Trim()
        [Console]::Error.WriteLine("${label} found vulnerabilities in ${file}:`n$output")
        exit 2
    }
}

switch ($file) {
    "Cargo.toml" {
        if (Get-Command "cargo" -ErrorAction SilentlyContinue) {
            $audit = cargo audit --version 2>$null
            if ($audit) { Run-Audit "cargo" @("audit", "--quiet") "cargo audit" }
        }
    }
    "package.json" {
        if (Get-Command "npm" -ErrorAction SilentlyContinue) {
            Run-Audit "npm" @("audit", "--audit-level=high") "npm audit"
        }
    }
    { $_ -in @("requirements.txt", "pyproject.toml") } {
        if (Get-Command "pip-audit" -ErrorAction SilentlyContinue) {
            Run-Audit "pip-audit" @("--quiet") "pip-audit"
        }
    }
}
exit 0
