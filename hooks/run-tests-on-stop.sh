#!/usr/bin/env bash
# Stop hook -- run tests after Claude's turn, inject failures back so Claude fixes them
# Registered in settings.json under hooks.Stop alongside update-docs-reminder

set -e

json=$(cat)

if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('stop_hook_active') else 1)" 2>/dev/null; then
  exit 0
fi

transcript=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

grep -q '"name":\s*"\(Write\|Edit\)"' "$transcript" 2>/dev/null || exit 0

git_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Detect project type
test_cmd=""
if [ -f "$git_root/Cargo.toml" ]; then
  test_cmd="cargo test --quiet"
elif [ -f "$git_root/pyproject.toml" ] || [ -f "$git_root/pytest.ini" ] || [ -f "$git_root/setup.py" ]; then
  test_cmd="python3 -m pytest --tb=short -q"
elif [ -f "$git_root/package.json" ]; then
  if node -e "const p=require('$git_root/package.json'); process.exit(p.scripts&&p.scripts.test?0:1)" 2>/dev/null; then
    test_cmd="npm test -- --run"
  elif command -v npx >/dev/null 2>&1; then
    test_cmd="npx vitest run --reporter=verbose"
  fi
elif [ -f "$git_root/Makefile" ] && grep -q '^test:' "$git_root/Makefile" 2>/dev/null; then
  test_cmd="make test"
fi

[ -z "$test_cmd" ] && exit 0

# Check first word of command is available
first_cmd=$(echo "$test_cmd" | cut -d' ' -f1)
command -v "$first_cmd" >/dev/null 2>&1 || exit 0

# Run with timeout (60s)
output=$(cd "$git_root" && timeout 60 sh -c "$test_cmd" 2>&1) && status=0 || status=$?

if [ "$status" -ne 0 ]; then
  echo "Tests failed after your changes. Fix the failures:"
  echo ""
  echo "$output"
  exit 2
fi

exit 0
