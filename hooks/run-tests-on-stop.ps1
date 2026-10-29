#Requires -Version 7.0
#!/usr/bin/env pwsh
# Stop hook -- run tests after Claude's turn; inject failures so Claude self-corrects

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data -or $data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$lines = @(Get-Content $transcriptPath -Encoding utf8 -ErrorAction SilentlyContinue)
if (-not $lines) { exit 0 }

# --- current-turn scan: keep IDENTICAL across the 3 Stop hooks (.ps1 + .sh) ---
# Anchor = last REAL user prompt: a "type":"user" record that is neither a
# tool_result carrier nor isMeta (Skill bodies, agent messages and Stop-hook
# feedback are injected mid-turn as isMeta user records). Edits = tool_use
# inside records whose top-level type is "assistant" only: other record types
# (e.g. api-request-blob) replay the WHOLE history. -AsHashtable because plain
# ConvertFrom-Json throws on valid JSON with keys differing only by case;
# comparisons are case-sensitive to match the Python half.
function ConvertFrom-JsonLine([string]$line) {
    try { return ($line | ConvertFrom-Json -AsHashtable -ErrorAction Stop) } catch { return $null }
}
function Get-MessageContent($rec) {
    $msg = $rec['message']
    # Leading comma: a function returning a 1-element array would otherwise
    # unroll it to the bare element and the IList checks below would fail.
    if ($msg -is [System.Collections.IDictionary]) { return ,$msg['content'] }
    return $null
}
$lastUserIdx = -1
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '"type"\s*:\s*"user"') { continue }
    $rec = ConvertFrom-JsonLine $lines[$i]
    if ($rec -isnot [System.Collections.IDictionary]) {
        if ($lines[$i] -notmatch '"tool_result"') { $lastUserIdx = $i; break }
        continue
    }
    if ($rec['type'] -cne 'user' -or $rec['isMeta'] -eq $true) { continue }
    $content = Get-MessageContent $rec
    $isToolResult = $false
    if ($content -is [System.Collections.IList]) {
        foreach ($c in $content) {
            if ($c -is [System.Collections.IDictionary] -and $c['type'] -ceq 'tool_result') { $isToolResult = $true; break }
        }
    }
    if (-not $isToolResult) { $lastUserIdx = $i; break }
}
$EditTools = @('Write', 'Edit', 'MultiEdit')
$editedPaths = [System.Collections.Generic.List[string]]::new()
$hasEdit = $false
for ($i = $lastUserIdx + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch '"name"\s*:\s*"(Write|Edit|MultiEdit)"') { continue }
    $rec = ConvertFrom-JsonLine $lines[$i]
    if ($rec -isnot [System.Collections.IDictionary] -or $rec['type'] -cne 'assistant') { continue }
    $content = Get-MessageContent $rec
    if ($content -isnot [System.Collections.IList]) { continue }
    foreach ($c in $content) {
        if ($c -is [System.Collections.IDictionary] -and $c['type'] -ceq 'tool_use' -and $EditTools -ccontains $c['name']) {
            $hasEdit = $true
            $inp = $c['input']
            if ($inp -is [System.Collections.IDictionary] -and $inp['file_path']) { $editedPaths.Add([string]$inp['file_path']) }
        }
    }
}
# --- end current-turn scan ---
if (-not $hasEdit) { exit 0 }

$workDir = if ($data.cwd -and (Test-Path $data.cwd)) { $data.cwd } else { Get-Location }
$gitRoot = git -C $workDir rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitRoot) { exit 0 }
$gitRoot = $gitRoot.Trim()

# Detect project type; $testLine is a single command line run through cmd.exe
$testLine = $null

if (Test-Path (Join-Path $gitRoot "Cargo.toml")) {
    $testLine = "cargo test --quiet"
} elseif ((Test-Path (Join-Path $gitRoot "pyproject.toml")) -or
          (Test-Path (Join-Path $gitRoot "pytest.ini")) -or
          (Test-Path (Join-Path $gitRoot "setup.py"))) {
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pyCmd -and $pyCmd.Source -notmatch 'WindowsApps') {
        $testLine = "python -m pytest --tb=short -q"
    }
} elseif (Test-Path (Join-Path $gitRoot "package.json")) {
    $pkg = Get-Content (Join-Path $gitRoot "package.json") | ConvertFrom-Json
    $testScript = $pkg.scripts?.test
    if ($testScript) {
        # Respect the project's own runner. Extra flags only for a KNOWN
        # runner: `npm test -- --run` breaks e.g. `node --test`.
        $testLine = ($testScript -match 'vitest' -and $testScript -notmatch '\brun\b') ? "npm test -- --run" : "npm test"
    } elseif (Test-Path (Join-Path $gitRoot "node_modules\.bin\vitest.cmd")) {
        # Fallback only when the project actually ships vitest -- never
        # trigger an implicit npx download of an undeclared runner.
        $testLine = "npx --no-install vitest run"
    }
} elseif (Test-Path (Join-Path $gitRoot "Makefile")) {
    if ((Get-Content (Join-Path $gitRoot "Makefile") -Raw) -match '(?m)^test:') {
        $testLine = "make test"
    }
}

if (-not $testLine) { exit 0 }
$firstWord = ($testLine -split ' ')[0]
if (-not (Get-Command $firstWord -ErrorAction SilentlyContinue)) { exit 0 }

# Run through cmd.exe: npm/npx/make on Windows are .cmd shims that
# Process.Start(UseShellExecute=$false) cannot launch directly.
$psi = [System.Diagnostics.ProcessStartInfo]@{
    FileName               = ($env:ComSpec ? $env:ComSpec : 'cmd.exe')
    Arguments              = "/d /s /c `"$testLine`""
    WorkingDirectory       = $gitRoot
    RedirectStandardOutput = $true
    RedirectStandardError  = $true
    UseShellExecute        = $false
    CreateNoWindow         = $true
}

$proc = [System.Diagnostics.Process]::Start($psi)
# Drain both streams asynchronously BEFORE waiting: a synchronous ReadToEnd
# can block past the timeout (and risks deadlock when both pipes fill).
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()
$finished = $proc.WaitForExit(60000)
if (-not $finished) {
    try { $proc.Kill($true) } catch {}
    $proc.WaitForExit()
    exit 0
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result

if ($proc.ExitCode -ne 0) {
    [Console]::Error.WriteLine("Tests failed after your changes. Fix the failures:`n`n$("$stdout`n$stderr".Trim())")
    exit 2
}

exit 0
