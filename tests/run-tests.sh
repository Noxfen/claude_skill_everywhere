#!/usr/bin/env bash
# Regression suite (Linux/macOS/WSL) -- exercises the behaviors from the Sept 2026 audit.
# Self-contained: every test runs against a throwaway CLAUDE_CONFIG_DIR fixture;
# the real user configuration is never touched. Requires python3 (like the hooks).
#
# Usage: bash tests/run-tests.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FX="$(mktemp -d)"
PASS=0; FAIL=0

# Paths embedded in JSON payloads must be native: on MSYS/Git-Bash only argv
# gets converted, so translate explicitly; on Linux cygpath is absent (no-op).
native() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

assert() {  # assert <cond-exit-code> <name>
  if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok  $2"; else FAIL=$((FAIL+1)); echo "  FAIL $2"; fi
}
count_json() {  # count_json <file> <python-expr using d>
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"
}

# ---------------------------------------------------------------- installers
echo "== installers =="
CFG="$FX/cfg"; mkdir -p "$CFG"; echo '{}' > "$CFG/settings.json"
export CLAUDE_CONFIG_DIR="$CFG"

bash "$REPO_ROOT/hooks/install.sh" >/dev/null 2>&1; rc=$?
assert $rc "hooks/install.sh succeeds on empty {} settings"
[ "$(count_json "$CFG/settings.json" "len(d['hooks'])")" = "5" ]; assert $? "all 5 hook events registered"

bash "$REPO_ROOT/statusline/install.sh" >/dev/null 2>&1; rc=$?
assert $rc "statusline/install.sh succeeds on fixture settings"
[ "$(count_json "$CFG/settings.json" "d['statusLine']['type']")" = "command" ]; assert $? "statusLine patched"

# statusline installer must preserve extra user keys
python3 - "$CFG/settings.json" <<'PYEOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["statusLine"]["padding"] = 3; json.dump(d, open(p, "w"))
PYEOF
bash "$REPO_ROOT/statusline/install.sh" >/dev/null 2>&1
[ "$(count_json "$CFG/settings.json" "d['statusLine'].get('padding')")" = "3" ]; assert $? "statusline install preserves extra statusLine keys"

# --force preserves foreign sibling commands and stays idempotent
python3 - "$CFG/settings.json" <<'PYEOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for e in d["hooks"]["Stop"]:
    if any("run-tests-on-stop" in h["command"] for h in e["hooks"]):
        e["hooks"].append({"type": "command", "command": "echo CUSTOM_UNRELATED"}); break
json.dump(d, open(p, "w"), indent=2)
PYEOF
bash "$REPO_ROOT/hooks/install.sh" --force >/dev/null 2>&1
bash "$REPO_ROOT/hooks/install.sh" --force >/dev/null 2>&1
[ "$(count_json "$CFG/settings.json" "sum(1 for e in d['hooks']['Stop'] for h in e['hooks'] if h['command']=='echo CUSTOM_UNRELATED')")" = "1" ]
assert $? "--force preserves foreign sibling command"
[ "$(count_json "$CFG/settings.json" "len(d['hooks']['Stop'])")" = "4" ]; assert $? "--force twice does not grow Stop entries"

unset CLAUDE_CONFIG_DIR

# ---------------------------------------------------------- turn delimitation
echo "== turn delimitation (update-docs-reminder) =="
DOCS="$REPO_ROOT/hooks/update-docs-reminder.sh"
ROOT_N="$(native "$REPO_ROOT")"

cat > "$FX/cur.jsonl" <<'EOF'
{"type":"user","message":{"content":"do it"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"x"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
EOF
echo "{\"transcript_path\":\"$(native "$FX/cur.jsonl")\",\"cwd\":\"$ROOT_N\"}" | bash "$DOCS" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ]; assert $? "fires on current-turn edit"

cat > "$FX/prev.jsonl" <<'EOF'
{"type":"user","message":{"content":"first"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"x"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
{"type":"user","message":{"content":"explain what a tool_result is, no edits please"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"answer"}]}}
EOF
echo "{\"transcript_path\":\"$(native "$FX/prev.jsonl")\",\"cwd\":\"$ROOT_N\"}" | bash "$DOCS" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; assert $? "silent when edits are in a previous turn (prompt mentions tool_result)"

cat > "$FX/spaced.jsonl" <<'EOF'
{ "type" : "user", "message": { "content": "do it" } }
{ "type" : "assistant", "message": { "content": [ { "type": "tool_use", "name": "Write", "input": { "file_path": "x" } } ] } }
EOF
echo "{\"transcript_path\":\"$(native "$FX/spaced.jsonl")\",\"cwd\":\"$ROOT_N\"}" | bash "$DOCS" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ]; assert $? "fires on whitespace-formatted JSON"

# ------------------------------------------------------------- unsafe-rust
echo "== unsafe-rust-blocker =="
RUST="$REPO_ROOT/hooks/unsafe-rust-blocker.sh"
mkdir -p "$FX/rust"
printf '// SAFETY: ptr is valid for the lifetime of the call\nunsafe { do_thing(ptr) }\n' > "$FX/rust/lib.rs"
RLIB="$(native "$FX/rust/lib.rs")"

echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$RLIB\",\"old_string\":\"unsafe { do_thing(ptr) }\",\"new_string\":\"unsafe { do_thing_v2(ptr) }\"}}" | bash "$RUST" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; assert $? "allows edit when SAFETY survives on the line above"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$RLIB\",\"old_string\":\"// SAFETY: ptr is valid for the lifetime of the call\\n\",\"new_string\":\"\"}}" | bash "$RUST" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ]; assert $? "blocks when the edit DELETES the SAFETY comment"
echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$(native "$FX/rust/other.rs")\",\"content\":\"let msg = \\\"found unsafe { in source\\\";\"}}" | bash "$RUST" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; assert $? "ignores 'unsafe {' inside a string literal"

# ------------------------------------------------------------- auto-sync
echo "== auto-sync =="
if command -v git >/dev/null 2>&1; then
  # A linked worktree has a .git FILE; the hook must still recognise it.
  git init -q "$FX/main" && git -C "$FX/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$FX/main" worktree add -q "$FX/wt" -b wt 2>/dev/null
  [ -f "$FX/wt/.git" ]; assert $? "fixture worktree has a .git file"
  CLAUDE_SKILL_EVERYWHERE_DIR="$FX/wt" bash "$REPO_ROOT/hooks/auto-sync.sh" >/dev/null 2>&1; rc=$?
  assert $rc "auto-sync.sh exits 0 when pointed at a worktree (no remote: pull fails silently, not skipped)"
else
  echo "  skip (git not available)"
fi

# -------------------------------------------------------------- statusline
echo "== statusline (needs jq; skipped when missing) =="
if command -v jq >/dev/null 2>&1; then
  SL="$REPO_ROOT/statusline/statusline-command.sh"
  echo '{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":1790000000},"weekly":{"used_percentage":30,"resets_at":1790400000}}}' | bash "$SL" | grep -q "7d"; assert $? "renders 7d bar from 'weekly' field"
  echo '{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":1790000000},"seven_day":{"used_percentage":30,"resets_at":1790400000}}}' | bash "$SL" | grep -q "7d"; assert $? "renders 7d bar from 'seven_day' field"
else
  echo "  skip (jq not available)"
fi

# ------------------------------------------------------- run-tests-on-stop
echo "== run-tests-on-stop (needs node+npm+git; skipped when missing) =="
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  PROJ="$FX/nodeproj"; mkdir -p "$PROJ"; git init -q "$PROJ"
  echo '{ "name": "fixture", "version": "1.0.0", "scripts": { "test": "node --test" } }' > "$PROJ/package.json"
  printf "const { test } = require('node:test');\nconst assert = require('node:assert');\ntest('ok', () => assert.strictEqual(1, 1));\n" > "$PROJ/pass.test.js"
  TESTS="$REPO_ROOT/hooks/run-tests-on-stop.sh"
  PROJ_N="$(native "$PROJ")"

  echo "{\"transcript_path\":\"$(native "$FX/cur.jsonl")\",\"cwd\":\"$PROJ_N\"}" | bash "$TESTS" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ]; assert $? "passing 'node --test' project exits 0 (runner respected, no forced --run)"

  printf "const { test } = require('node:test');\nconst assert = require('node:assert');\ntest('boom', () => assert.strictEqual(1, 2));\n" > "$PROJ/fail.test.js"
  out=$(echo "{\"transcript_path\":\"$(native "$FX/cur.jsonl")\",\"cwd\":\"$PROJ_N\"}" | bash "$TESTS" 2>&1); rc=$?
  [ "$rc" -eq 2 ]; assert $? "failing test injects exit 2"
  echo "$out" | grep -q "node --test"; assert $? "injected output is the real npm run"
else
  echo "  skip (node/npm/git not available)"
fi

# ------------------------------------------------------------------ summary
echo ""
echo "passed: $PASS  failed: $FAIL"
rm -rf "$FX"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
