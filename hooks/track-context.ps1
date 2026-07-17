#Requires -Version 7.0
#!/usr/bin/env pwsh
# PostToolUse hook -- tracks context window usage from API-reported token counts
# Writes ~/.claude/context-estimate.json for statusline and compact-warning hook
#
# Reads the real context size from the last assistant message's `message.usage`
# (input_tokens + cache_read_input_tokens + cache_creation_input_tokens + output_tokens)
# instead of estimating chars/4 over the transcript, which overestimates badly:
# JSONL metadata, file-history snapshots, and microcompacted tool results are in
# the transcript but not in the model's context. Falls back to chars/4 only when
# no usage entry exists yet (start of session).

trap { Add-Content "$env:TEMP\claude-hook-errors.log" "track-context: $($_.Exception.Message) L$($_.InvocationInfo.ScriptLineNumber)" -Encoding utf8; exit 0 }

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$ClaudeDir    = $env:CLAUDE_CONFIG_DIR ?? (Join-Path $env:USERPROFILE ".claude")
$EstimateFile = Join-Path $ClaudeDir "context-estimate.json"

$lines = @(Get-Content $transcriptPath -Encoding utf8 -ErrorAction SilentlyContinue)
if (-not $lines) { exit 0 }

# Context window size in tokens (override per model via env)
$window = [double]($env:CLAUDE_CONTEXT_WINDOW ?? 1000000)

# Walk backwards to the most recent main-chain assistant message with usage data
$tokensEst = 0
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $l = $lines[$i]
    if ($l -notmatch '"type":"assistant"' -or $l -notmatch '"usage"') { continue }
    if ($l -match '"isSidechain":\s*true') { continue }  # subagents have their own context
    $obj = $l | ConvertFrom-Json -ErrorAction SilentlyContinue
    $u = $obj.message.usage
    if (-not $u -or $null -eq $u.input_tokens) { continue }
    $tokensEst = [int64]($u.input_tokens ?? 0) +
                 [int64]($u.cache_read_input_tokens ?? 0) +
                 [int64]($u.cache_creation_input_tokens ?? 0) +
                 [int64]($u.output_tokens ?? 0)
    break
}

# Fallback: chars/4 heuristic from last compact boundary (no usage yet)
if ($tokensEst -eq 0) {
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
    $tokensEst = [int64][math]::Round($activeCharCount / 4)
}

$pct = [math]::Min([math]::Round(($tokensEst / $window) * 100, 1), 100)

[PSCustomObject]@{
    pct        = $pct
    tokens_est = $tokensEst
    updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
} | ConvertTo-Json | Set-Content $EstimateFile -Encoding utf8

exit 0
