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
import json, re, sys
# --- current-turn scan: keep IDENTICAL across the 3 Stop hooks (.ps1 + .sh) ---
# Anchor = last REAL user prompt: a "type":"user" record that is neither a
# tool_result carrier nor isMeta (Skill bodies, agent messages and Stop-hook
# feedback are injected mid-turn as isMeta user records). Edits = tool_use
# inside records whose top-level type is "assistant" only: other record types
# (e.g. api-request-blob) replay the WHOLE history.
USER_RE = re.compile(r'"type"\s*:\s*"user"')
EDIT_RE = re.compile(r'"name"\s*:\s*"(Write|Edit|MultiEdit)"')
EDIT_TOOLS = ("Write", "Edit", "MultiEdit")

def parse(line):
    try:
        return json.loads(line)
    except Exception:
        return None

def content_of(rec):
    msg = rec.get("message")
    return msg.get("content") if isinstance(msg, dict) else None

lines = open(sys.argv[1], encoding="utf-8", errors="replace").readlines()
anchor = -1
for i in range(len(lines) - 1, -1, -1):
    l = lines[i]
    if not USER_RE.search(l):
        continue
    rec = parse(l)
    if not isinstance(rec, dict):
        if "tool_result" not in l:
            anchor = i
            break
        continue
    if rec.get("type") != "user" or rec.get("isMeta") is True:
        continue
    content = content_of(rec)
    if isinstance(content, list) and any(
        isinstance(c, dict) and c.get("type") == "tool_result" for c in content
    ):
        continue
    anchor = i
    break

edited = []
for l in lines[anchor + 1:]:
    if not EDIT_RE.search(l):
        continue
    rec = parse(l)
    if not isinstance(rec, dict) or rec.get("type") != "assistant":
        continue
    content = content_of(rec)
    if not isinstance(content, list):
        continue
    for c in content:
        if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") in EDIT_TOOLS:
            inp = c.get("input")
            edited.append(inp.get("file_path", "") if isinstance(inp, dict) else "")
# --- end current-turn scan ---
for fp in edited:
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
