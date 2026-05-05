#Requires -Version 7.0
#!/usr/bin/env pwsh
# Stop hook -- remind Claude to update CLAUDE.md / README.md after file edits

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data -or $data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$content = Get-Content $transcriptPath -Raw -ErrorAction SilentlyContinue
if ($content -notmatch '"name":\s*"(Write|Edit)"') { exit 0 }

$gitRoot = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitRoot) { exit 0 }
$gitRoot = $gitRoot.Trim()

$docs = @(
    "CLAUDE.md", "README.md"
) | Where-Object { Test-Path (Join-Path $gitRoot $_) }

if ($docs.Count -eq 0) { exit 0 }

Write-Output "Hai appena modificato dei file nel progetto. Controlla se $($docs -join ', ') va aggiornato per riflettere le modifiche fatte. Se necessario, aggiornali ora."
exit 2
