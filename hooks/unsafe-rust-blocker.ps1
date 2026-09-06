#Requires -Version 7.0
#!/usr/bin/env pwsh
# PreToolUse hook -- block unsafe Rust blocks without // SAFETY: comment.
# Forces justification of memory-unsafe code. Exit 2 + stderr blocks the operation.

trap { exit 0 }

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data) { exit 0 }

$tool = $data.tool_name
if ($tool -notin @("Write", "Edit", "MultiEdit")) { exit 0 }

$path = $data.tool_input.file_path
if (-not $path -or $path -notmatch '\.rs$') { exit 0 }

# Reconstruct the RESULTING file content: checking only the replacement
# fragment misses surrounding context (a SAFETY comment on the line above
# survives) and cannot see a SAFETY comment being deleted.
function Get-BaseContent {
    if (Test-Path $path) { return (Get-Content $path -Raw -Encoding utf8 -ErrorAction SilentlyContinue) ?? "" }
    return ""
}
function Apply-Replace([string]$base, [string]$old, [string]$new, [bool]$all) {
    if (-not $old -or -not $base.Contains($old)) { return $null }
    if ($all) { return $base.Replace($old, $new) }
    $idx = $base.IndexOf($old)
    return $base.Substring(0, $idx) + $new + $base.Substring($idx + $old.Length)
}

$newContent = if ($tool -eq "Write") {
    $data.tool_input.content
} elseif ($tool -eq "Edit") {
    $applied = Apply-Replace (Get-BaseContent) $data.tool_input.old_string $data.tool_input.new_string ([bool]$data.tool_input.replace_all)
    $applied ?? $data.tool_input.new_string   # fallback: analyse the fragment alone
} elseif ($tool -eq "MultiEdit") {
    $acc = Get-BaseContent
    foreach ($e in $data.tool_input.edits) {
        $r = Apply-Replace $acc $e.old_string $e.new_string ([bool]$e.replace_all)
        if ($null -ne $r) { $acc = $r }
    }
    $acc
}
if (-not $newContent) { exit 0 }

# Heuristic scanner: it does not lex Rust. It skips an `unsafe` inside a
# string literal on the same line (odd count of unescaped quotes before the
# match) but cannot see block comments or raw strings.
$lines = $newContent -split "`n"
for ($i = 0; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], 'unsafe\s*[\{(]')
    if ($m.Success) {
        $before = $lines[$i].Substring(0, $m.Index)
        $quoteCount = ([regex]::Matches($before, '(?<!\\)"')).Count
        if ($quoteCount % 2 -eq 1) { continue }  # inside a string literal
        # Allow if SAFETY: comment within 3 lines before or on the same line
        $hasSafety = $false
        for ($j = [Math]::Max(0, $i - 3); $j -le $i; $j++) {
            if ($lines[$j] -match '//\s*SAFETY:') { $hasSafety = $true; break }
        }
        if (-not $hasSafety) {
            [Console]::Error.WriteLine("BLOCKED: unsafe Rust block at line $($i + 1) in $path without '// SAFETY:' comment. Add a SAFETY comment explaining the invariants you uphold.")
            exit 2
        }
    }
}
exit 0
