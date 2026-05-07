#!/usr/bin/env bash
# PreToolUse hook -- block unsafe Rust blocks without // SAFETY: comment.
# Forces justification of memory-unsafe code. Exit 2 + stderr blocks the operation.

python3 <<'PYEOF'
import json, sys, re

data = json.load(sys.stdin)
tool = data.get("tool_name", "")
if tool not in ("Write", "Edit", "MultiEdit"):
    sys.exit(0)

path = data.get("tool_input", {}).get("file_path", "")
if not path or not path.endswith(".rs"):
    sys.exit(0)

ti = data.get("tool_input", {})
if tool == "Write":
    new_content = ti.get("content", "")
elif tool == "Edit":
    new_content = ti.get("new_string", "")
else:
    new_content = "\n".join(e.get("new_string", "") for e in ti.get("edits", []))

if not new_content:
    sys.exit(0)

lines = new_content.split("\n")
unsafe_re = re.compile(r"unsafe\s*[\{(]")
safety_re = re.compile(r"//\s*SAFETY:")

for i, line in enumerate(lines):
    if unsafe_re.search(line):
        has_safety = any(safety_re.search(lines[j]) for j in range(max(0, i - 3), i + 1))
        if not has_safety:
            print(f"BLOCKED: unsafe Rust block at line {i + 1} in {path} without '// SAFETY:' comment. Add a SAFETY comment explaining the invariants you uphold.", file=sys.stderr)
            sys.exit(2)

sys.exit(0)
PYEOF

exit $?
