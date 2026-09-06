#!/usr/bin/env bash
# PreToolUse hook -- block unsafe Rust blocks without // SAFETY: comment.
# Forces justification of memory-unsafe code. Exit 2 + stderr blocks the operation.

# Capture stdin first; heredoc would otherwise occupy python3's stdin and swallow the hook payload.
HOOK_INPUT="$(cat)"
export HOOK_INPUT

python3 <<'PYEOF'
import json, os, sys, re

raw = os.environ.get("HOOK_INPUT", "")
if not raw.strip():
    sys.exit(0)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)

tool = data.get("tool_name", "")
if tool not in ("Write", "Edit", "MultiEdit"):
    sys.exit(0)

path = data.get("tool_input", {}).get("file_path", "")
if not path or not path.endswith(".rs"):
    sys.exit(0)

ti = data.get("tool_input", {})

# Reconstruct the RESULTING file content: checking only the replacement
# fragment misses the surrounding context (a SAFETY comment on the line
# above survives) and cannot see a SAFETY comment being deleted.
def base_content():
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""

if tool == "Write":
    new_content = ti.get("content", "")
elif tool == "Edit":
    base = base_content()
    old, new = ti.get("old_string", ""), ti.get("new_string", "")
    if old and old in base:
        new_content = base.replace(old, new) if ti.get("replace_all") else base.replace(old, new, 1)
    else:
        new_content = new  # fallback: analyse the fragment alone
else:  # MultiEdit
    new_content = base_content()
    for e in ti.get("edits", []):
        old, new = e.get("old_string", ""), e.get("new_string", "")
        if old and old in new_content:
            new_content = new_content.replace(old, new) if e.get("replace_all") else new_content.replace(old, new, 1)

if not new_content:
    sys.exit(0)

# Heuristic scanner: it does not lex Rust. It skips an `unsafe` that sits
# inside a string literal on the same line (odd count of unescaped quotes
# before the match) but cannot see block comments or raw strings.
lines = new_content.split("\n")
unsafe_re = re.compile(r"unsafe\s*[\{(]")
safety_re = re.compile(r"//\s*SAFETY:")

def in_string(line, idx):
    return len(re.findall(r'(?<!\\)"', line[:idx])) % 2 == 1

for i, line in enumerate(lines):
    m = unsafe_re.search(line)
    if m and not in_string(line, m.start()):
        has_safety = any(safety_re.search(lines[j]) for j in range(max(0, i - 3), i + 1))
        if not has_safety:
            print(f"BLOCKED: unsafe Rust block at line {i + 1} in {path} without '// SAFETY:' comment. Add a SAFETY comment explaining the invariants you uphold.", file=sys.stderr)
            sys.exit(2)

sys.exit(0)
PYEOF

exit $?
