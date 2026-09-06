---
name: powershell-best-practices
description: >
  PowerShell scripting best practices for robust, maintainable scripts and modules.
  Activates when writing or reviewing .ps1/.psm1/.psd1 files, or when the user asks to
  "write a powershell script", "PS1 script", "powershell function", "pwsh", mentions
  PSScriptAnalyzer, or discusses PowerShell patterns. Covers both Windows PowerShell 5.1
  and PowerShell 7+ (cross-platform).
version: 1.0.0
---

# PowerShell Best Practices

Apply these rules whenever writing or reviewing PowerShell scripts.

## Quality gate

```powershell
Invoke-ScriptAnalyzer -Path script.ps1 -Severity Warning,Error
```

Install if missing: `Install-Module PSScriptAnalyzer -Scope CurrentUser`

## Script header

```powershell
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputPath,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = "Stop"
```

- `[CmdletBinding()]` gives `-Verbose` and `-Debug` for free; `-WhatIf`/`-Confirm` require `[CmdletBinding(SupportsShouldProcess)]` AND guarding the operation with `if ($PSCmdlet.ShouldProcess($target)) { ... }`
- `$ErrorActionPreference = "Stop"` — treat all errors as terminating
- `#Requires` — document minimum PS version explicitly

## Naming conventions

- Cmdlets: `Verb-Noun` with approved verbs (`Get-Verb` to list them)
- Variables: `$PascalCase` for module-level, `$camelCase` acceptable for local
- Constants: `$script:MAX_RETRIES = 3` or `Set-Variable -Option ReadOnly`
- No abbreviations in public function names (`Get-UserAccount` not `Get-UsrAcc`)

## Error handling

```powershell
# try/catch for recoverable errors
try {
    $result = Invoke-RestMethod -Uri $url -Method Get
} catch [System.Net.WebException] {
    Write-Warning "Network error: $_"   # NB: with ErrorActionPreference=Stop,
    return $null                        # Write-Error is TERMINATING -- it would
} catch {                               # throw again and never reach `return`
    throw  # re-throw unexpected errors
}

# With $ErrorActionPreference = "Stop", Write-Error terminates too:
# use Write-Warning for non-fatal messages, throw for fatal errors
```

Never use `trap` in modern PS — use `try/catch/finally`.

## Output and logging

```powershell
# Streams: use the right one
Write-Verbose "Processing file $path"   # -Verbose flag controlled
Write-Debug "Internal state: $state"    # -Debug flag controlled
Write-Warning "File missing, skipping"  # yellow warning
Write-Error "Fatal: cannot continue"    # error stream
Write-Output $result                    # pipeline output (or just: $result)

# Never Write-Host in functions/modules (breaks pipeline, no redirection)
# Write-Host OK only in interactive scripts/menus
```

## Variables and scope

```powershell
# Explicit scope when needed
$script:Config = @{}    # script scope
$global:Debug  = $true  # global (avoid)

# Splatting for long parameter lists
$params = @{
    Path    = $InputPath
    Force   = $Force
    Verbose = $VerbosePreference -eq "Continue"
}
Copy-Item @params
```

## Avoid common pitfalls

```powershell
# PS5.1: Set-Content -Encoding utf8 writes UTF-8 WITH BOM
# Fix: use .NET directly
[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))

# Pipeline chain operators (&&, ||) only in PS7+
# PS5.1: use if ($LASTEXITCODE -eq 0) { ... }

# $null comparison: put $null on LEFT
if ($null -eq $value) { ... }    # correct
if ($value -eq $null) { ... }    # wrong -- $value could be array

# String comparison is case-insensitive by default
if ($str -ceq "Exact") { ... }   # -ceq for case-sensitive
```

## Functions and modules

```powershell
function Get-ProcessedData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$InputData,

        [ValidateSet("json", "csv", "xml")]
        [string]$Format = "json"
    )
    process {
        # process block for pipeline support
        # ...
    }
}
```

- Always `process {}` block for pipeline-aware functions
- `[ValidateSet]`, `[ValidateRange]`, `[ValidatePattern]` for parameter validation
- Comment-based help: `<# .SYNOPSIS ... .PARAMETER ... .EXAMPLE ... #>`

## Cross-platform (PS7+)

```powershell
# Path separator
Join-Path $home "documents" "file.txt"   # correct -- cross-platform
"$home\documents\file.txt"               # wrong -- Windows only

# Detect OS
if ($IsWindows) { ... }
if ($IsLinux -or $IsMacOS) { ... }

# Use $PSScriptRoot not $MyInvocation.MyCommand.Path
$configPath = Join-Path $PSScriptRoot "config.json"
```

## Security

- Never store credentials in plain text — use `Get-Credential` or SecretStore
- Avoid `Invoke-Expression` — equivalent to `eval` in bash
- `-ExecutionPolicy Bypass` only in CI/installer scripts, never in production modules
- Validate all external input with `[ValidatePattern]` or explicit checks
