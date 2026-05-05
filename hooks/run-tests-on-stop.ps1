#!/usr/bin/env pwsh
# Stop hook -- run tests after Claude's turn, inject failures back so Claude fixes them
# Registered in settings.json under hooks.Stop alongside update-docs-reminder

$json = [Console]::In.ReadToEnd()
try { $data = $json | ConvertFrom-Json } catch { exit 0 }

if ($data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$content = Get-Content $transcriptPath -Raw -ErrorAction SilentlyContinue
if (-not ($content -match '"name":\s*"(Write|Edit)"')) { exit 0 }

$gitRoot = & git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitRoot) { exit 0 }
$gitRoot = $gitRoot.Trim()

# Detect project type and run appropriate tests
$testCmd = $null
$testArgs = @()

if (Test-Path (Join-Path $gitRoot "Cargo.toml")) {
    $testCmd = "cargo"
    $testArgs = @("test", "--quiet")
} elseif ((Test-Path (Join-Path $gitRoot "pyproject.toml")) -or
          (Test-Path (Join-Path $gitRoot "pytest.ini")) -or
          (Test-Path (Join-Path $gitRoot "setup.py"))) {
    $testCmd = "python"
    $testArgs = @("-m", "pytest", "--tb=short", "-q")
} elseif (Test-Path (Join-Path $gitRoot "package.json")) {
    $pkg = Get-Content (Join-Path $gitRoot "package.json") -Raw | ConvertFrom-Json
    if ($pkg.scripts.test) {
        $testCmd = "npm"
        $testArgs = @("test", "--", "--run")
    } elseif (Get-Command npx -ErrorAction SilentlyContinue) {
        $testCmd = "npx"
        $testArgs = @("vitest", "run", "--reporter=verbose")
    }
} elseif (Test-Path (Join-Path $gitRoot "Makefile")) {
    $content2 = Get-Content (Join-Path $gitRoot "Makefile") -Raw
    if ($content2 -match '^test:') {
        $testCmd = "make"
        $testArgs = @("test")
    }
}

if (-not $testCmd) { exit 0 }
if (-not (Get-Command $testCmd -ErrorAction SilentlyContinue)) { exit 0 }

# Run tests with 60s timeout -- use Process to capture stdout+stderr correctly in PS5.1
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $testCmd
$psi.Arguments = $testArgs -join " "
$psi.WorkingDirectory = $gitRoot
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$finished = $proc.WaitForExit(60000)
if (-not $finished) { $proc.Kill(); exit 0 }
$exitCode = $proc.ExitCode

if ($exitCode -ne 0) {
    Write-Output "Tests failed after your changes. Fix the failures:"
    Write-Output ""
    Write-Output "$stdout`n$stderr".Trim()
    exit 2
}

exit 0
