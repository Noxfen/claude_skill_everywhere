#!/usr/bin/env bash
# Stop hook -- warns when context estimate reaches threshold, asks Claude to /compact

input=$(cat)
if echo "$input" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('stop_hook_active') else 1)" 2>/dev/null; then
  exit 0
fi

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ESTIMATE_FILE="$CLAUDE_DIR/context-estimate.json"
THRESHOLD="${CLAUDE_COMPACT_THRESHOLD:-80}"

[ -f "$ESTIMATE_FILE" ] || exit 0

python3 - "$ESTIMATE_FILE" "$THRESHOLD" <<'PYEOF'
import json, sys, time

with open(sys.argv[1]) as f:
    est = json.load(f)

threshold = float(sys.argv[2])
age = time.time() - est.get("updated_at", 0)

if age > 600:
    sys.exit(0)
if est.get("pct", 0) < threshold:
    sys.exit(0)

tokens_k = round(est.get("tokens_est", 0) / 1000)
print(f"[CONTEXT WARNING] Contesto al ~{est['pct']}% (~{tokens_k}k token stimati su 1M). Esegui /compact ora per comprimere la conversazione e liberare contesto.")
sys.exit(2)
PYEOF

exit $?
