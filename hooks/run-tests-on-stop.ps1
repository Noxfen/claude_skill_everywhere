#Requires -Version 7.0
#!/usr/bin/env pwsh
# Stop hook -- run tests after Claude's turn; inject failures so Claude self-corrects

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data -or $data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$content = Get-Content $transcriptPath -Raw -ErrorAction SilentlyContinue
if ($content -notmatch '"name":\s*"(Write|Edit)"') { exit 0 }

$gitRoot = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitRoot) { exit 0 }
$gitRoot = $gitRoot.Trim()

# Detect project type
$testCmd  = $null
$testArgs = @()

if (Test-Path (Join-Path $gitRoot "Cargo.toml")) {
    $testCmd = "cargo"; $testArgs = @("test", "--quiet")
} elseif ((Test-Path (Join-Path $gitRoot "pyproject.toml")) -or
          (Test-Path (Join-Path $gitRoot "pytest.ini")) -or
          (Test-Path (Join-Path $gitRoot "setup.py"))) {
    $testCmd = "python"; $testArgs = @("-m", "pytest", "--tb=short", "-q")
} elseif (Test-Path (Join-Path $gitRoot "package.json")) {
    $pkg = Get-Content (Join-Path $gitRoot "package.json") | ConvertFrom-Json
    $testCmd = "npm"
    $testArgs = $pkg.scripts?.test ? @("test", "--", "--run") : @("exec", "vitest", "run")
} elseif (Test-Path (Join-Path $gitRoot "Makefile")) {
    if ((Get-Content (Join-Path $gitRoot "Makefile") -Raw) -match '^test:') {
        $testCmd = "make"; $testArgs = @("test")
    }
}

if (-not $testCmd -or -not (Get-Command $testCmd -ErrorAction SilentlyContinue)) { exit 0 }

# Run with 60s timeout via Process (reliable stdout+stderr capture)
$psi = [System.Diagnostics.ProcessStartInfo]@{
    FileName               = $testCmd
    Arguments              = $testArgs -join " "
    WorkingDirectory       = $gitRoot
    RedirectStandardOutput = $true
    RedirectStandardError  = $true
    UseShellExecute        = $false
    CreateNoWindow         = $true
}

$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$finished = $proc.WaitForExit(60000)
if (-not $finished) { $proc.Kill(); exit 0 }

if ($proc.ExitCode -ne 0) {
    Write-Output "Tests failed after your changes. Fix the failures:"
    Write-Output ""
    Write-Output "$stdout`n$stderr".Trim()
    exit 2
}

exit 0
