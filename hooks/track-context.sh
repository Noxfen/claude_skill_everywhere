#!/usr/bin/env bash
# PostToolUse hook -- tracks context window usage from API-reported token counts
# Writes ~/.claude/context-estimate.json for statusline and compact-warning hook
#
# Reads the real context size from the last assistant message's `message.usage`
# (input_tokens + cache_read_input_tokens + cache_creation_input_tokens + output_tokens)
# instead of estimating chars/4 over the transcript, which overestimates badly:
# JSONL metadata, file-history snapshots, and microcompacted tool results are in
# the transcript but not in the model's context. Falls back to chars/4 only when
# no usage entry exists yet (start of session).

input=$(cat)
transcript=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ESTIMATE_FILE="$CLAUDE_DIR/context-estimate.json"
WINDOW="${CLAUDE_CONTEXT_WINDOW:-1000000}"

python3 - "$transcript" "$ESTIMATE_FILE" "$WINDOW" <<'PYEOF'
import json, sys, time

transcript_path = sys.argv[1]
estimate_file   = sys.argv[2]
window          = float(sys.argv[3])

with open(transcript_path, encoding="utf-8", errors="replace") as f:
    lines = f.readlines()

# Walk backwards to the most recent main-chain assistant message with usage data
tokens_est = 0
for i in range(len(lines) - 1, -1, -1):
    l = lines[i]
    if '"type":"assistant"' not in l or '"usage"' not in l:
        continue
    try:
        e = json.loads(l)
    except Exception:
        continue
    if e.get("isSidechain"):  # subagents have their own context
        continue
    u = (e.get("message") or {}).get("usage") or {}
    if u.get("input_tokens") is None:
        continue
    tokens_est = (
        (u.get("input_tokens") or 0)
        + (u.get("cache_read_input_tokens") or 0)
        + (u.get("cache_creation_input_tokens") or 0)
        + (u.get("output_tokens") or 0)
    )
    break

# Fallback: chars/4 heuristic from last compact boundary (no usage yet)
if tokens_est == 0:
    active_start = 0
    for i in range(len(lines) - 1, -1, -1):
        if '"type":"user"' in lines[i] and '"content":"This session is being continued' in lines[i]:
            active_start = i
            break
    tokens_est = round(sum(len(l) for l in lines[active_start:]) / 4)

pct = min(round(tokens_est / window * 100, 1), 100)

with open(estimate_file, "w", encoding="utf-8") as f:
    json.dump({"pct": pct, "tokens_est": tokens_est, "updated_at": int(time.time())}, f)
PYEOF

exit 0
