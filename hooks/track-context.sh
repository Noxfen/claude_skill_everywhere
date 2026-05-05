#!/usr/bin/env bash
# PostToolUse hook -- estimates context window usage from transcript size
# Writes ~/.claude/context-estimate.json for statusline and compact-warning hook
# After /compact the transcript grows but active context resets — count only from
# last compact boundary ("This session is being continued") forward.

input=$(cat)
transcript=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ESTIMATE_FILE="$CLAUDE_DIR/context-estimate.json"

python3 - "$transcript" "$ESTIMATE_FILE" <<'PYEOF'
import json, sys, time, math

transcript_path = sys.argv[1]
estimate_file   = sys.argv[2]

with open(transcript_path, encoding="utf-8", errors="replace") as f:
    lines = f.readlines()

active_start = 0
for i in range(len(lines) - 1, -1, -1):
    if '"type":"user"' in lines[i] and '"content":"This session is being continued' in lines[i]:
        active_start = i
        break

active_chars = sum(len(l) for l in lines[active_start:])
tokens_est   = round(active_chars / 4)
pct          = min(round(tokens_est / 1_000_000.0 * 100, 1), 100)

with open(estimate_file, "w", encoding="utf-8") as f:
    json.dump({"pct": pct, "tokens_est": tokens_est, "updated_at": int(time.time())}, f)
PYEOF

exit 0
