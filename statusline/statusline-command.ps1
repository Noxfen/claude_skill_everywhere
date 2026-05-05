#Requires -Version 7.0
#!/usr/bin/env pwsh
# Claude Code statusline -- shows 5h and weekly rate limit bars with color coding.
# Output: 5h [████████░░] 78% -> 14:30   |   7d [████░░░░░░] 42% -> Gio 08:00

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data) { exit 0 }

$esc   = [char]27
$reset = "${esc}[0m"
$dim   = "${esc}[2m"

function Get-Bar([double]$pct) {
    $filled = [math]::Min([math]::Floor($pct / 10), 10)
    return ([string][char]0x2588 * $filled) + ([string][char]0x2591 * (10 - $filled))
}

function Get-Color([double]$pct) {
    if ($pct -ge 80) { return "${esc}[31m" }
    if ($pct -ge 50) { return "${esc}[33m" }
    return "${esc}[32m"
}

$itaDays = @("Dom","Lun","Mar","Mer","Gio","Ven","Sab")

function Format-Segment([string]$label, [double]$pct, [long]$resetsAt, [bool]$weekly = $false) {
    $pctFmt = [math]::Round($pct, 0)
    $bar    = Get-Bar $pct
    $color  = Get-Color $pct
    $seg    = "${color}${label} [${bar}] ${pctFmt}%"

    if ($resetsAt -gt 0) {
        try {
            $dt = [System.DateTimeOffset]::FromUnixTimeSeconds($resetsAt).LocalDateTime
            $timeStr = $weekly ? "$($itaDays[[int]$dt.DayOfWeek]) $($dt.ToString('HH:mm'))" : $dt.ToString("HH:mm")
            $seg += " ${dim}-> ${timeStr}"
        } catch {}
    }
    return "$seg$reset"
}

$rl = $data.rate_limits
$pct5 = $rl?.five_hour?.used_percentage
if ($null -eq $pct5) { exit 0 }

$seg5 = Format-Segment "5h" $pct5 ($rl.five_hour?.resets_at ?? 0)

$pctW = $rl?.seven_day?.used_percentage
$segW = $null -ne $pctW ? (Format-Segment "7d" $pctW ($rl.seven_day?.resets_at ?? 0) $true) : $null

# Context estimate block
$segCtx = $null
$ClaudeDir    = $env:CLAUDE_CONFIG_DIR ?? (Join-Path $env:USERPROFILE ".claude")
$EstimateFile = Join-Path $ClaudeDir "context-estimate.json"
if (Test-Path $EstimateFile) {
    try {
        $est = Get-Content $EstimateFile -Raw | ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $est.updated_at
        if ($age -le 300 -and $est.pct -gt 0) {
            $colorCtx = Get-Color $est.pct
            $barCtx   = Get-Bar $est.pct
            $pctFmt   = [math]::Round($est.pct, 0)
            $segCtx   = "${colorCtx}ctx [${barCtx}] ${pctFmt}%~${reset}"
        }
    } catch {}
}

$parts = @($seg5) + @($segW | Where-Object { $_ }) + @($segCtx | Where-Object { $_ })
Write-Host -NoNewline ($parts -join "  ${dim}|${reset}  ")
