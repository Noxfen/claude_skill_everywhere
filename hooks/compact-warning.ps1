#Requires -Version 7.0
#!/usr/bin/env pwsh
# Stop hook -- warns when context estimate reaches threshold, asks Claude to /compact

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data -or $data.stop_hook_active) { exit 0 }

$ClaudeDir    = $env:CLAUDE_CONFIG_DIR ?? (Join-Path $env:USERPROFILE ".claude")
$EstimateFile = Join-Path $ClaudeDir "context-estimate.json"

if (-not (Test-Path $EstimateFile)) { exit 0 }

$threshold = [int]($env:CLAUDE_COMPACT_THRESHOLD ?? 80)

$est = Get-Content $EstimateFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $est) { exit 0 }

# Skip if estimate is stale (>10 minutes)
$age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $est.updated_at
if ($age -gt 600) { exit 0 }

if ($est.pct -lt $threshold) { exit 0 }

$tokensK = [math]::Round($est.tokens_est / 1000)
[Console]::Error.WriteLine("[CONTEXT WARNING] Context at ~$($est.pct)% (~${tokensK}k estimated tokens of 1M). Run /compact now to compress the conversation and free up context.")
exit 2
