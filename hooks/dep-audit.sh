#!/usr/bin/env bash
# PostToolUse hook -- run security audit when dependency files change.
# Cargo.toml -> cargo audit, package.json -> npm audit, pyproject.toml/requirements.txt -> pip-audit.
# Exit 2 + stderr injects vulnerability summary to Claude.

json=$(cat)

path=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)
tool=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

case "$tool" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac
[ -z "$path" ] && exit 0

file=$(basename "$path")
dir=$(dirname "$path")
[ ! -d "$dir" ] && exit 0

run_audit() {
    local cmd="$1" label="$2"
    local output rc
    # GNU `timeout` is absent on stock macOS: fall back to no limit rather
    # than mis-reporting command-not-found as vulnerabilities.
    if command -v timeout >/dev/null 2>&1; then
        output=$(cd "$dir" && timeout 45 sh -c "$cmd" 2>&1); rc=$?
    else
        output=$(cd "$dir" && sh -c "$cmd" 2>&1); rc=$?
    fi
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
        echo "${label} reported issues for ${file}:" >&2
        echo "$output" >&2
        exit 2
    fi
}

case "$file" in
    Cargo.toml)
        if command -v cargo >/dev/null && cargo audit --version >/dev/null 2>&1; then
            run_audit "cargo audit --quiet" "cargo audit"
        fi
        ;;
    package.json)
        if command -v npm >/dev/null; then
            run_audit "npm audit --audit-level=high" "npm audit"
        fi
        ;;
    requirements.txt)
        # Audit the edited file itself (-r); an environment audit says nothing
        # about this project's pinned deps. NB: pip-audit has no --quiet flag.
        if command -v pip-audit >/dev/null; then
            run_audit "pip-audit --progress-spinner off -r \"$file\"" "pip-audit"
        fi
        ;;
    # pyproject.toml deliberately skipped: pip-audit cannot audit it directly
    # and an environment audit would report an unrelated interpreter's deps.
esac

exit 0
