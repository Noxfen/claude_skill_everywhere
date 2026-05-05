#!/usr/bin/env pwsh
# Stop hook — reminds Claude to update CLAUDE.md / README.md after file edits
# Registered in settings.json under hooks.Stop
# Install: run hooks/install.ps1

$json = [Console]::In.ReadToEnd()
try { $data = $json | ConvertFrom-Json } catch { exit 0 }

if ($data.stop_hook_active) { exit 0 }

$transcriptPath = $data.transcript_path
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$content = Get-Content $transcriptPath -Raw -ErrorAction SilentlyContinue
if (-not ($content -match '"name":\s*"(Write|Edit)"')) { exit 0 }

$gitRoot = & git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitRoot) { exit 0 }

$gitRoot = $gitRoot.Trim()

$docsToCheck = @()
if (Test-Path (Join-Path $gitRoot "CLAUDE.md"))  { $docsToCheck += "CLAUDE.md" }
if (Test-Path (Join-Path $gitRoot "README.md"))  { $docsToCheck += "README.md" }
if ($docsToCheck.Count -eq 0) { exit 0 }

$list = $docsToCheck -join ", "
Write-Output "Hai appena modificato dei file nel progetto. Controlla se $list va aggiornato per riflettere le modifiche fatte. Se necessario, aggiornali ora."
exit 2
