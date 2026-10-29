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
sys.exit(0 if edited else 1)
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
