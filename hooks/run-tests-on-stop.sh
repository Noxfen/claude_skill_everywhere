#!/usr/bin/env bash
# Stop hook -- run tests after Claude's turn, inject failures back so Claude fixes them
# Registered in settings.json under hooks.Stop alongside update-docs-reminder
# No `set -e`: command-substitution assignments (python3 may be missing) must
# not abort the hook -- every failure path is handled explicitly.

json=$(cat)

if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('stop_hook_active') else 1)" 2>/dev/null; then
  exit 0
fi

transcript=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# Only look at the CURRENT turn: anchor on the last real user prompt.
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

# Detect project type
test_cmd=""
if [ -f "$git_root/Cargo.toml" ]; then
  test_cmd="cargo test --quiet"
elif [ -f "$git_root/pyproject.toml" ] || [ -f "$git_root/pytest.ini" ] || [ -f "$git_root/setup.py" ]; then
  test_cmd="python3 -m pytest --tb=short -q"
elif [ -f "$git_root/package.json" ]; then
  # Respect the project's own runner: extra flags only for a KNOWN runner
  # (`npm test -- --run` breaks e.g. `node --test`). Fall back to vitest only
  # when the project actually ships it -- no implicit npx download.
  test_script=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('scripts',{}).get('test',''))" "$git_root/package.json" 2>/dev/null)
  if [ -n "$test_script" ]; then
    case "$test_script" in
      *vitest*run*) test_cmd="npm test" ;;
      *vitest*)     test_cmd="npm test -- --run" ;;
      *)            test_cmd="npm test" ;;
    esac
  elif [ -x "$git_root/node_modules/.bin/vitest" ]; then
    test_cmd="npx --no-install vitest run"
  fi
elif [ -f "$git_root/Makefile" ] && grep -q '^test:' "$git_root/Makefile" 2>/dev/null; then
  test_cmd="make test"
fi

[ -z "$test_cmd" ] && exit 0

# Check first word of command is available
first_cmd=$(echo "$test_cmd" | cut -d' ' -f1)
command -v "$first_cmd" >/dev/null 2>&1 || exit 0

# Run with timeout (60s). GNU `timeout` is absent on stock macOS: fall back
# to no limit rather than mis-reporting command-not-found as a test failure.
if command -v timeout >/dev/null 2>&1; then
  output=$(cd "$git_root" && timeout 60 sh -c "$test_cmd" 2>&1) && status=0 || status=$?
else
  output=$(cd "$git_root" && sh -c "$test_cmd" 2>&1) && status=0 || status=$?
fi

# Timeout (124) is not a test failure -- mirror the PS1 version, which exits 0
[ "$status" -eq 124 ] && exit 0

if [ "$status" -ne 0 ]; then
  echo "Tests failed after your changes. Fix the failures:" >&2
  echo "" >&2
  echo "$output" >&2
  exit 2
fi

exit 0
