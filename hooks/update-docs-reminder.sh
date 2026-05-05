#!/usr/bin/env bash
# Stop hook — reminds Claude to update CLAUDE.md / README.md after file edits
# Registered in settings.json under hooks.Stop
# Install: bash hooks/install.sh

set -e

json=$(cat)

# Bail if stop_hook_active to avoid infinite loop
if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('stop_hook_active') else 1)" 2>/dev/null; then
  exit 0
fi

transcript=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

if ! grep -q '"name":\s*"\(Write\|Edit\)"' "$transcript" 2>/dev/null; then
  exit 0
fi

git_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

docs=()
[ -f "$git_root/CLAUDE.md" ] && docs+=("CLAUDE.md")
[ -f "$git_root/README.md" ] && docs+=("README.md")
[ ${#docs[@]} -eq 0 ] && exit 0

list=$(IFS=", "; echo "${docs[*]}")
echo "Hai appena modificato dei file nel progetto. Controlla se $list va aggiornato per riflettere le modifiche fatte. Se necessario, aggiornali ora." >&2
exit 2
