#Requires -Version 7.0
#!/usr/bin/env pwsh
# PostToolUse hook -- estimates context window usage from transcript size
# Writes ~/.claude/context-estimate.json for statusline and compact-warning hook
# After /compact the transcript grows but active context resets — we find the
# last compact boundary ("This session is being continued") and count only from there.

trap { Add-Content "$env:TEMP\claude-hook-errors.log" "track-context: $($_.Exception.Message) L$($_.InvocationInfo.ScriptLineNumber)" -Encoding utf8; exit 0 }

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$ClaudeDir    = $env:CLAUDE_CONFIG_DIR ?? (Join-Path $env:USERPROFILE ".claude")
$EstimateFile = Join-Path $ClaudeDir "context-estimate.json"

$lines = Get-Content $transcriptPath -Encoding utf8 -ErrorAction SilentlyContinue
if (-not $lines) { exit 0 }

# Find last compact boundary — /compact inserts a user message with this exact content prefix
$activeStart = 0
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match '"type":"user"' -and $lines[$i] -match '"content":"This session is being continued') {
        $activeStart = $i; break
    }
}

$activeCharCount = 0
for ($i = $activeStart; $i -lt $lines.Count; $i++) {
    $activeCharCount += $lines[$i].Length
}

$tokensEst = [math]::Round($activeCharCount / 4)
$pct       = [math]::Min([math]::Round(($tokensEst / 1000000.0) * 100, 1), 100)

[PSCustomObject]@{
    pct        = $pct
    tokens_est = $tokensEst
    updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
} | ConvertTo-Json | Set-Content $EstimateFile -Encoding utf8

exit 0
