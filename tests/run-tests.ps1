#Requires -Version 7.0
#!/usr/bin/env pwsh
# Regression suite (Windows) -- exercises the behaviors from the Sept 2026 audit.
# Self-contained: every test runs against a throwaway CLAUDE_CONFIG_DIR fixture;
# the real user configuration is never touched.
#
# Usage: pwsh -NoProfile -File tests\run-tests.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Fx = Join-Path ([System.IO.Path]::GetTempPath()) ("noxfen-tests-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $Fx | Out-Null

$script:Pass = 0
$script:Fail = 0

function Assert([bool]$cond, [string]$name) {
    if ($cond) { $script:Pass++; Write-Host "  ok  $name" -ForegroundColor Green }
    else       { $script:Fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}
function New-Fixture([string]$name) {
    $d = Join-Path $Fx $name
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Set-Content (Join-Path $d "settings.json") '{}' -Encoding utf8
    return $d
}
function U([string]$p) { $p.Replace('\', [string][char]0x2F) }

# ---------------------------------------------------------------- installers
Write-Host "== installers =="
$cfg = New-Fixture "cfg"
$env:CLAUDE_CONFIG_DIR = $cfg

pwsh -NoProfile -File (Join-Path $RepoRoot "hooks\install.ps1") *> $null
Assert ($LASTEXITCODE -eq 0) "hooks/install.ps1 succeeds on empty {} settings"
$j = Get-Content (Join-Path $cfg "settings.json") -Raw | ConvertFrom-Json
Assert (@($j.hooks.PSObject.Properties.Name).Count -eq 5) "all 5 hook events registered"

pwsh -NoProfile -File (Join-Path $RepoRoot "statusline\install.ps1") *> $null
Assert ($LASTEXITCODE -eq 0) "statusline/install.ps1 succeeds on fixture settings"
$j = Get-Content (Join-Path $cfg "settings.json") -Raw | ConvertFrom-Json
Assert ($j.statusLine.type -eq "command") "statusLine patched"

# -Force preserves foreign sibling commands and stays idempotent
$entry = $j.hooks.Stop | Where-Object { $_.hooks.command -like "*run-tests-on-stop*" } | Select-Object -First 1
$entry.hooks = @($entry.hooks) + @([PSCustomObject]@{ type = "command"; command = "echo CUSTOM_UNRELATED" })
$j | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $cfg "settings.json") -Encoding utf8
pwsh -NoProfile -File (Join-Path $RepoRoot "hooks\install.ps1") -Force *> $null
pwsh -NoProfile -File (Join-Path $RepoRoot "hooks\install.ps1") -Force *> $null
$j = Get-Content (Join-Path $cfg "settings.json") -Raw | ConvertFrom-Json
$custom = @($j.hooks.Stop.hooks.command | Where-Object { $_ -eq "echo CUSTOM_UNRELATED" }).Count
Assert ($custom -eq 1) "-Force preserves foreign sibling command"
Assert (@($j.hooks.Stop).Count -eq 4) "-Force twice does not grow Stop entries"

Remove-Item Env:\CLAUDE_CONFIG_DIR

# ---------------------------------------------------------- turn delimitation
Write-Host "== turn delimitation (update-docs-reminder) =="
$docsHook = Join-Path $RepoRoot "hooks\update-docs-reminder.ps1"

$tCur = Join-Path $Fx "cur.jsonl"
@'
{"type":"user","message":{"content":"do it"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"x"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
'@ | Set-Content $tCur -Encoding utf8
"{`"transcript_path`":`"$(U $tCur)`",`"cwd`":`"$(U $RepoRoot)`"}" | pwsh -NoProfile -File $docsHook 2>$null
Assert ($LASTEXITCODE -eq 2) "fires on current-turn edit"

$tPrev = Join-Path $Fx "prev.jsonl"
@'
{"type":"user","message":{"content":"first"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"x"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
{"type":"user","message":{"content":"explain what a tool_result is, no edits please"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"answer"}]}}
'@ | Set-Content $tPrev -Encoding utf8
"{`"transcript_path`":`"$(U $tPrev)`",`"cwd`":`"$(U $RepoRoot)`"}" | pwsh -NoProfile -File $docsHook 2>$null
Assert ($LASTEXITCODE -eq 0) "silent when edits are in a previous turn (prompt mentions tool_result)"

$tSp = Join-Path $Fx "spaced.jsonl"
@'
{ "type" : "user", "message": { "content": "do it" } }
{ "type" : "assistant", "message": { "content": [ { "type": "tool_use", "name": "Write", "input": { "file_path": "x" } } ] } }
'@ | Set-Content $tSp -Encoding utf8
"{`"transcript_path`":`"$(U $tSp)`",`"cwd`":`"$(U $RepoRoot)`"}" | pwsh -NoProfile -File $docsHook 2>$null
Assert ($LASTEXITCODE -eq 2) "fires on whitespace-formatted JSON"

# ------------------------------------------------------------- unsafe-rust
Write-Host "== unsafe-rust-blocker =="
$rustHook = Join-Path $RepoRoot "hooks\unsafe-rust-blocker.ps1"
$rustDir = Join-Path $Fx "rust"
New-Item -ItemType Directory -Force -Path $rustDir | Out-Null
Set-Content (Join-Path $rustDir "lib.rs") "// SAFETY: ptr is valid for the lifetime of the call`nunsafe { do_thing(ptr) }`n" -Encoding utf8
$rlib = U (Join-Path $rustDir "lib.rs")

"{`"tool_name`":`"Edit`",`"tool_input`":{`"file_path`":`"$rlib`",`"old_string`":`"unsafe { do_thing(ptr) }`",`"new_string`":`"unsafe { do_thing_v2(ptr) }`"}}" | pwsh -NoProfile -File $rustHook 2>$null
Assert ($LASTEXITCODE -eq 0) "allows edit when SAFETY survives on the line above"
"{`"tool_name`":`"Edit`",`"tool_input`":{`"file_path`":`"$rlib`",`"old_string`":`"// SAFETY: ptr is valid for the lifetime of the call\n`",`"new_string`":`"`"}}" | pwsh -NoProfile -File $rustHook 2>$null
Assert ($LASTEXITCODE -eq 2) "blocks when the edit DELETES the SAFETY comment"
"{`"tool_name`":`"Write`",`"tool_input`":{`"file_path`":`"$(U (Join-Path $rustDir 'other.rs'))`",`"content`":`"let msg = \`"found unsafe { in source\`";`"}}" | pwsh -NoProfile -File $rustHook 2>$null
Assert ($LASTEXITCODE -eq 0) "ignores 'unsafe {' inside a string literal"

# ------------------------------------------------------------- lint-on-edit
Write-Host "== lint-on-edit =="
$def = Get-Content (Join-Path $RepoRoot "hooks\lint-on-edit.ps1") -Raw
$fn = [regex]::Match($def, 'function Run-Format.*?\n}', 'Singleline').Value
Invoke-Expression $fn
function Has-Command([string]$cmd) { $true }
function Probe-Args { $script:GotArgs = $args.Count }
$script:GotArgs = -1
$global:LASTEXITCODE = 0
Run-Format "Probe-Args" @("--write", "test.js") | Out-Null
Assert ($script:GotArgs -eq 2) "Run-Format passes arguments through (regression: `$args collision)"

# -------------------------------------------------------------- statusline
Write-Host "== statusline =="
$sl = Join-Path $RepoRoot "statusline\statusline-command.ps1"
$outW = '{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":1790000000},"weekly":{"used_percentage":30,"resets_at":1790400000}}}' | pwsh -NoProfile -File $sl
Assert ($outW -match '7d') "renders 7d bar from 'weekly' field"
$outS = '{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":1790000000},"seven_day":{"used_percentage":30,"resets_at":1790400000}}}' | pwsh -NoProfile -File $sl
Assert ($outS -match '7d') "renders 7d bar from 'seven_day' field"

# ------------------------------------------------------- run-tests-on-stop
Write-Host "== run-tests-on-stop (needs node+npm+git; skipped when missing) =="
$haveNode = (Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue) -and (Get-Command git -ErrorAction SilentlyContinue)
if ($haveNode) {
    $proj = Join-Path $Fx "nodeproj"
    New-Item -ItemType Directory -Force -Path $proj | Out-Null
    git -C $proj init -q 2>$null
    Set-Content (Join-Path $proj "package.json") '{ "name": "fixture", "version": "1.0.0", "scripts": { "test": "node --test" } }' -Encoding utf8
    Set-Content (Join-Path $proj "pass.test.js") "const { test } = require('node:test');`nconst assert = require('node:assert');`ntest('ok', () => assert.strictEqual(1, 1));" -Encoding utf8
    $testsHook = Join-Path $RepoRoot "hooks\run-tests-on-stop.ps1"

    "{`"transcript_path`":`"$(U $tCur)`",`"cwd`":`"$(U $proj)`"}" | pwsh -NoProfile -File $testsHook 2>$null
    Assert ($LASTEXITCODE -eq 0) "passing 'node --test' project exits 0 (runner respected, npm launches via cmd.exe)"

    Set-Content (Join-Path $proj "fail.test.js") "const { test } = require('node:test');`nconst assert = require('node:assert');`ntest('boom', () => assert.strictEqual(1, 2));" -Encoding utf8
    $errOut = "{`"transcript_path`":`"$(U $tCur)`",`"cwd`":`"$(U $proj)`"}" | pwsh -NoProfile -File $testsHook 2>&1
    Assert ($LASTEXITCODE -eq 2) "failing test injects exit 2"
    Assert (("$errOut" -match 'node --test')) "injected output is the real npm run"
} else {
    Write-Host "  skip (node/npm/git not available)" -ForegroundColor Yellow
}

# ------------------------------------------------------------------ summary
Write-Host ""
Write-Host "passed: $script:Pass  failed: $script:Fail"
Remove-Item $Fx -Recurse -Force -ErrorAction SilentlyContinue
exit ($script:Fail -gt 0 ? 1 : 0)
