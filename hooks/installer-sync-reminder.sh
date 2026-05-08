#!/usr/bin/env bash
# Stop hook -- remind Claude to update install.* when files in hooks/, mcp/, statusline/, or sources.json are edited

set -e

json=$(cat)

# Bail if stop_hook_active to avoid loops
if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('stop_hook_active') else 1)" 2>/dev/null; then
  exit 0
fi

transcript=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# Find last user message line number
last_user_line=$(grep -n '"type":"user"' "$transcript" 2>/dev/null | tail -1 | cut -d: -f1)
last_user_line=${last_user_line:-0}

# Extract edited paths from Write/Edit/MultiEdit tool_use after last user message
paths=$(tail -n +"$((last_user_line + 1))" "$transcript" | python3 -c '
import sys, json
for line in sys.stdin:
    try:
        e = json.loads(line)
        msg = e.get("message", {})
        content = msg.get("content") or []
        if not isinstance(content, list):
            continue
        for c in content:
            if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") in ("Write","Edit","MultiEdit"):
                fp = (c.get("input") or {}).get("file_path")
                if fp: print(fp)
    except Exception:
        pass
')

[ -z "$paths" ] && exit 0

workdir=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
git_root=$(git -C "${workdir:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0

needs_hooks=0
needs_mcp=0
needs_statusline=0
needs_root=0

while IFS= read -r p; do
    [ -z "$p" ] && continue
    # Normalize separators
    abs="${p//\\//}"
    root="${git_root//\\//}"
    case "$abs" in
        "$root"/*) rel="${abs#$root/}" ;;
        *) continue ;;
    esac

    case "$rel" in
        hooks/install.ps1|hooks/install.sh)           continue ;;
        mcp/install.ps1|mcp/install.sh)               continue ;;
        statusline/install.ps1|statusline/install.sh) continue ;;
        install.ps1|install.sh)                       continue ;;
        hooks/*)      needs_hooks=1 ;;
        mcp/*)        needs_mcp=1 ;;
        statusline/*) needs_statusline=1 ;;
        sources.json) needs_root=1 ;;
    esac
done <<< "$paths"

[ "$needs_hooks" = 0 ] && [ "$needs_mcp" = 0 ] && [ "$needs_statusline" = 0 ] && [ "$needs_root" = 0 ] && exit 0

{
    echo "Hai modificato file impattanti per la sync cross-machine. Verifica che gli installer siano aggiornati:"
    [ "$needs_hooks" = 1 ]      && echo "  - hooks/install.ps1 + hooks/install.sh (nuovi/rinominati hook scripts)"
    [ "$needs_mcp" = 1 ]        && echo "  - mcp/install.ps1 + mcp/install.sh (nuovi server MCP)"
    [ "$needs_statusline" = 1 ] && echo "  - statusline/install.ps1 + statusline/install.sh (cambiamenti statusline)"
    [ "$needs_root" = 1 ]       && echo "  - install.ps1 + install.sh root (sources.json modificato)"
    echo "Aggiornali se necessario per non rompere la sync."
} >&2

exit 2
