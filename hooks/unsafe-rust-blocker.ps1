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

# Get the new content depending on tool
$newContent = if ($tool -eq "Write") {
    $data.tool_input.content
} elseif ($tool -eq "Edit") {
    $data.tool_input.new_string
} elseif ($tool -eq "MultiEdit") {
    ($data.tool_input.edits | ForEach-Object { $_.new_string }) -join "`n"
}
if (-not $newContent) { exit 0 }

$lines = $newContent -split "`n"
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'unsafe\s*[\{(]') {
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
