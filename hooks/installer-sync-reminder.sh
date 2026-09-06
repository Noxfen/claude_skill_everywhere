#!/usr/bin/env bash
# Stop hook -- remind Claude to update install.* when files in hooks/, mcp/, statusline/, or sources.json are edited
# No `set -e`: command-substitution assignments (python3 may be missing) must
# not abort the hook -- every failure path is handled explicitly.

json=$(cat)

# Bail if stop_hook_active to avoid loops
if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('stop_hook_active') else 1)" 2>/dev/null; then
  exit 0
fi

transcript=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# Anchor on the last REAL user prompt (JSON-parsed: a structural tool_result
# entry is also "type":"user", and a prompt may merely MENTION tool_result),
# then extract edited paths from Write/Edit/MultiEdit tool_use after it.
paths=$(python3 - "$transcript" <<'PYEOF' 2>/dev/null
import json, sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").readlines()
anchor = -1
for i in range(len(lines) - 1, -1, -1):
    l = lines[i]
    if '"user"' not in l or '"type"' not in l:
        continue
    try:
        rec = json.loads(l)
    except Exception:
        if "tool_result" not in l:
            anchor = i; break
        continue
    if rec.get("type") != "user":
        continue
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, list) and any(
        isinstance(c, dict) and c.get("type") == "tool_result" for c in content
    ):
        continue
    anchor = i; break
for l in lines[anchor + 1:]:
    try:
        e = json.loads(l)
    except Exception:
        continue
    content = (e.get("message") or {}).get("content")
    if not isinstance(content, list):
        continue
    for c in content:
        if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") in ("Write", "Edit", "MultiEdit"):
            fp = (c.get("input") or {}).get("file_path")
            if fp:
                print(fp)
PYEOF
)

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
    echo "You modified files that affect cross-machine sync. Verify the installers are up to date:"
    [ "$needs_hooks" = 1 ]      && echo "  - hooks/install.ps1 + hooks/install.sh (new/renamed hook scripts)"
    [ "$needs_mcp" = 1 ]        && echo "  - mcp/install.ps1 + mcp/install.sh (new MCP servers)"
    [ "$needs_statusline" = 1 ] && echo "  - statusline/install.ps1 + statusline/install.sh (statusline changes)"
    [ "$needs_root" = 1 ]       && echo "  - root install.ps1 + install.sh (sources.json modified)"
    echo "Update them if needed so the sync does not break."
} >&2

exit 2
