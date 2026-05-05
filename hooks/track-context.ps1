#Requires -Version 7.0
#!/usr/bin/env pwsh
# PostToolUse hook -- estimates context window usage from transcript size
# Writes ~/.claude/context-estimate.json for statusline and compact-warning hook

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$ClaudeDir   = $env:CLAUDE_CONFIG_DIR ?? (Join-Path $env:USERPROFILE ".claude")
$EstimateFile = Join-Path $ClaudeDir "context-estimate.json"

$bytes      = (Get-Item $transcriptPath).Length
$tokensEst  = [math]::Round($bytes / 4)
$pct        = [math]::Min([math]::Round(($tokensEst / 1000000.0) * 100, 1), 100)

[PSCustomObject]@{
    pct        = $pct
    tokens_est = $tokensEst
    updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
} | ConvertTo-Json | Set-Content $EstimateFile -Encoding utf8

exit 0
