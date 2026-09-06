#!/usr/bin/env bash
# Stop hook — reminds Claude to update CLAUDE.md / README.md after file edits
# Registered in settings.json under hooks.Stop
# Install: bash hooks/install.sh
# No `set -e`: command-substitution assignments (python3 may be missing) must
# not abort the hook -- every failure path is handled explicitly.

json=$(cat)

# Bail if stop_hook_active to avoid infinite loop
if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('stop_hook_active') else 1)" 2>/dev/null; then
  exit 0
fi

transcript=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# Find Write/Edit only after the last REAL user prompt (current turn only).
# Lines are parsed as JSON so a structural tool_result entry (also
# "type":"user") and a prompt that merely mentions "tool_result" are both
# classified correctly, regardless of JSON whitespace.
python3 - "$transcript" <<'PYEOF' 2>/dev/null || exit 0
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
    if '"name"' not in l or ("Write" not in l and "Edit" not in l):
        continue
    try:
        rec = json.loads(l)
    except Exception:
        sys.exit(0)
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, list) and any(
        isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") in ("Write", "Edit")
        for c in content
    ):
        sys.exit(0)
sys.exit(1)
PYEOF

workdir=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
git_root=$(git -C "${workdir:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0

docs=()
[ -f "$git_root/CLAUDE.md" ] && docs+=("CLAUDE.md")
[ -f "$git_root/README.md" ] && docs+=("README.md")
[ ${#docs[@]} -eq 0 ] && exit 0

list=$(IFS=", "; echo "${docs[*]}")
echo "You just modified project files. Check whether $list needs updating to reflect the changes. If so, update them now." >&2
exit 2
