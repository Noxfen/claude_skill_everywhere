#!/usr/bin/env bash
# PostToolUse hook — auto-format/lint file after Write or Edit
# Detects language from extension, runs appropriate tool if available.
# Silent on missing tools. Always exits 0 (informational only, never blocks).

set -e

json=$(cat)

tool=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
case "$tool" in Write|Edit) ;; *) exit 0 ;; esac

file=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null)

[ -z "$file" ] || [ ! -f "$file" ] && exit 0

ext="${file##*.}"

run_if_available() {
  command -v "$1" >/dev/null 2>&1 || return 0
  "$@" 2>/dev/null && echo "[lint] formatted: $file" || true
}

case "$ext" in
  rs)
    # Format single file; clippy needs workspace context
    run_if_available rustfmt "$file"
    # Run clippy from workspace root if in a cargo project
    cargo_root=$(cd "$(dirname "$file")" && cargo locate-project --message-format plain 2>/dev/null | xargs dirname 2>/dev/null)
    if [ -n "$cargo_root" ] && command -v cargo >/dev/null 2>&1; then
      cargo clippy --manifest-path "$cargo_root/Cargo.toml" --quiet 2>/dev/null || true
    fi
    ;;
  py)
    run_if_available ruff format "$file"
    run_if_available ruff check --fix --quiet "$file"
    ;;
  js|mjs|cjs)
    # Only run prettier/eslint if config exists in project
    proj_root=$(cd "$(dirname "$file")" && git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$proj_root" ]; then
      [ -f "$proj_root/.prettierrc" ] || [ -f "$proj_root/prettier.config.js" ] || \
      [ -f "$proj_root/prettier.config.ts" ] && run_if_available prettier --write "$file"
      [ -f "$proj_root/eslint.config.js" ] || [ -f "$proj_root/.eslintrc.js" ] || \
      [ -f "$proj_root/.eslintrc.json" ] && run_if_available eslint --fix --quiet "$file"
    fi
    ;;
  ts|tsx|jsx)
    proj_root=$(cd "$(dirname "$file")" && git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$proj_root" ]; then
      [ -f "$proj_root/.prettierrc" ] || [ -f "$proj_root/prettier.config.js" ] || \
      [ -f "$proj_root/prettier.config.ts" ] && run_if_available prettier --write "$file"
      [ -f "$proj_root/eslint.config.js" ] || [ -f "$proj_root/.eslintrc.js" ] || \
      [ -f "$proj_root/.eslintrc.json" ] && run_if_available eslint --fix --quiet "$file"
    fi
    ;;
  c|h|cpp|hpp|cc|cxx)
    run_if_available clang-format -i "$file"
    ;;
esac

exit 0
