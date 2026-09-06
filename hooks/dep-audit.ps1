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

function Run-Audit([string]$cmdLine, [string]$label) {
    # Run through cmd.exe: npm/pip-audit on Windows are .cmd/.exe shims that
    # Process.Start(UseShellExecute=$false) with a bare name cannot launch.
    $psi = [System.Diagnostics.ProcessStartInfo]@{
        FileName               = ($env:ComSpec ? $env:ComSpec : 'cmd.exe')
        Arguments              = "/d /s /c `"$cmdLine`""
        WorkingDirectory       = $dir
        RedirectStandardOutput = $true
        RedirectStandardError  = $true
        UseShellExecute        = $false
        CreateNoWindow         = $true
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    # Drain both streams asynchronously BEFORE waiting: a synchronous
    # ReadToEnd can block past the timeout (and risks pipe deadlock).
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $finished = $proc.WaitForExit(45000)
    if (-not $finished) {
        try { $proc.Kill($true) } catch {}
        $proc.WaitForExit()
        return
    }
    if ($proc.ExitCode -ne 0) {
        $output = "$($stdoutTask.Result)`n$($stderrTask.Result)".Trim()
        [Console]::Error.WriteLine("${label} reported issues for ${file}:`n$output")
        exit 2
    }
}

switch ($file) {
    "Cargo.toml" {
        if (Get-Command "cargo" -ErrorAction SilentlyContinue) {
            $audit = cargo audit --version 2>$null
            if ($audit) { Run-Audit "cargo audit --quiet" "cargo audit" }
        }
    }
    "package.json" {
        if (Get-Command "npm" -ErrorAction SilentlyContinue) {
            Run-Audit "npm audit --audit-level=high" "npm audit"
        }
    }
    "requirements.txt" {
        # Audit the edited file itself (-r); auditing the active Python
        # environment says nothing about this project's pinned deps.
        # NB: pip-audit has no --quiet flag.
        if (Get-Command "pip-audit" -ErrorAction SilentlyContinue) {
            Run-Audit "pip-audit --progress-spinner off -r `"$file`"" "pip-audit"
        }
    }
    # pyproject.toml deliberately skipped: pip-audit cannot audit it directly
    # and an environment audit would report an unrelated interpreter's deps.
}
exit 0
