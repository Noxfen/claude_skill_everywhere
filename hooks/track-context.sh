#!/usr/bin/env bash
# PostToolUse hook -- estimates context window usage from transcript size
# Writes ~/.claude/context-estimate.json for statusline and compact-warning hook

input=$(cat)
transcript=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ESTIMATE_FILE="$CLAUDE_DIR/context-estimate.json"

bytes=$(wc -c < "$transcript")
tokens_est=$(( bytes / 4 ))
pct=$(python3 -c "print(round(min($tokens_est / 1_000_000.0 * 100, 100), 1))")
updated_at=$(date +%s)

cat > "$ESTIMATE_FILE" <<EOF
{"pct": $pct, "tokens_est": $tokens_est, "updated_at": $updated_at}
EOF

exit 0
