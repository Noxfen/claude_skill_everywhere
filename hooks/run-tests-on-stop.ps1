#Requires -Version 7.0
#!/usr/bin/env pwsh
# Stop hook -- run tests after Claude's turn; inject failures so Claude self-corrects

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data -or $data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$lines = @(Get-Content $transcriptPath -Encoding utf8 -ErrorAction SilentlyContinue)
if (-not $lines) { exit 0 }

# Only look at the CURRENT turn: anchor on the last real user prompt.
# NB: tool_result entries are also "type":"user" lines, so they must be
# excluded or the anchor lands after every Write/Edit and the scan window
# is empty (the bug that made the sibling reminder hooks silent no-ops).
$lastUserIdx = -1
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match '"type":"user"' -and $lines[$i] -notmatch '"tool_result"') { $lastUserIdx = $i; break }
}
$hasEdit = $false
for ($i = $lastUserIdx + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '"name":\s*"(Write|Edit)"') { $hasEdit = $true; break }
}
if (-not $hasEdit) { exit 0 }

$workDir = if ($data.cwd -and (Test-Path $data.cwd)) { $data.cwd } else { Get-Location }
$gitRoot = git -C $workDir rev-parse --show-toplevel 2>$null
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
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pyCmd -and $pyCmd.Source -notmatch 'WindowsApps') {
        $testCmd = "python"; $testArgs = @("-m", "pytest", "--tb=short", "-q")
    }
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
    [Console]::Error.WriteLine("Tests failed after your changes. Fix the failures:`n`n$("$stdout`n$stderr".Trim())")
    exit 2
}

exit 0
