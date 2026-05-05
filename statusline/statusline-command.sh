#!/usr/bin/env bash
# Claude Code statusline -- shows 5h and weekly rate limit bars with color coding.
# Output: 5h [████████░░] 78% -> 14:30   |   7d [████░░░░░░] 42% -> Gio 08:00
# Requires: jq

input=$(cat)

make_bar() {
  local pct_int
  pct_int=$(printf '%.0f' "${1:-0}")
  [ "$pct_int" -gt 100 ] && pct_int=100
  local filled=$(( pct_int / 10 ))
  [ "$filled" -gt 10 ] && filled=10
  local bar="" i
  for ((i=0; i<filled; i++)); do bar+=$'\xe2\x96\x88'; done
  for ((i=0; i<(10-filled); i++)); do bar+=$'\xe2\x96\x91'; done
  echo "$bar"
}

get_color() {
  local pct_int
  pct_int=$(printf '%.0f' "${1:-0}")
  if   [ "$pct_int" -ge 80 ]; then printf $'\033[31m'
  elif [ "$pct_int" -ge 50 ]; then printf $'\033[33m'
  else                              printf $'\033[32m'
  fi
}

RESET=$'\033[0m'
DIM=$'\033[2m'
ITA_DAYS=("Dom" "Lun" "Mar" "Mer" "Gio" "Ven" "Sab")

format_segment() {
  local label="$1" pct="$2" resets_at="$3" weekly="${4:-0}"
  local pct_fmt bar color seg reset_str=""

  pct_fmt=$(printf '%.0f' "$pct")
  bar=$(make_bar "$pct")
  color=$(get_color "$pct")

  if [ -n "$resets_at" ] && [ "$resets_at" -gt 0 ] 2>/dev/null; then
    if [ "$weekly" = "1" ]; then
      dow=$(date -d "@${resets_at}" "+%w" 2>/dev/null || date -r "${resets_at}" "+%w" 2>/dev/null || echo "")
      time_str=$(date -d "@${resets_at}" "+%H:%M" 2>/dev/null || date -r "${resets_at}" "+%H:%M" 2>/dev/null || echo "")
      [ -n "$dow" ] && [ -n "$time_str" ] && reset_str="${ITA_DAYS[$dow]} ${time_str}"
    else
      reset_str=$(date -d "@${resets_at}" "+%H:%M" 2>/dev/null || date -r "${resets_at}" "+%H:%M" 2>/dev/null || echo "")
    fi
  fi

  seg="${color}${label} [${bar}] ${pct_fmt}%"
  [ -n "$reset_str" ] && seg+=" ${DIM}-> ${reset_str}"
  echo -n "${seg}${RESET}"
}

# 5h block
pct5=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
[ -z "$pct5" ] && exit 0

resets5=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
seg5=$(format_segment "5h" "$pct5" "$resets5" 0)

# Weekly block
pctW=$(echo "$input" | jq -r '.rate_limits.weekly.used_percentage // empty' 2>/dev/null || \
       echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)

segW=""
if [ -n "$pctW" ]; then
  resetsW=$(echo "$input" | jq -r '.rate_limits.weekly.resets_at // .rate_limits.seven_day.resets_at // 0')
  segW=$(format_segment "7d" "$pctW" "$resetsW" 1)
fi

# Context estimate block
segCtx=""
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ESTIMATE_FILE="$CLAUDE_DIR/context-estimate.json"
if [ -f "$ESTIMATE_FILE" ]; then
  segCtx=$(python3 - "$ESTIMATE_FILE" <<'PYEOF'
import json, sys, time
with open(sys.argv[1]) as f:
    est = json.load(f)
age = time.time() - est.get("updated_at", 0)
pct = est.get("pct", 0)
if age > 300 or pct <= 0:
    sys.exit(0)
pct_int = round(pct)
filled = min(pct_int // 10, 10)
bar = "\xe2\x96\x88" * filled + "\xe2\x96\x91" * (10 - filled)
color = "\033[31m" if pct_int >= 80 else ("\033[33m" if pct_int >= 50 else "\033[32m")
print(f"{color}ctx [{bar}] {pct_int}%~\033[0m", end="")
PYEOF
  )
fi

# --- output ---
sep="${DIM}|${RESET}"
out="$seg5"
[ -n "$segW"   ] && out="$out  $sep  $segW"
[ -n "$segCtx" ] && out="$out  $sep  $segCtx"
printf "%s" "$out"
