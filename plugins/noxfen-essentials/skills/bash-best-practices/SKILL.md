---
name: bash-best-practices
description: >
  Bash scripting best practices for robust, portable, production-quality shell scripts.
  Activates when writing or reviewing .sh files, or when the user asks to "write a bash script",
  "shell script", "bash function", "sh script", mentions shellcheck, or discusses bash patterns.
  Enforces defensive scripting, error handling, and POSIX compatibility where relevant.
version: 1.0.0
---

# Bash Best Practices

Apply these rules whenever writing or reviewing bash/shell scripts.

## Quality gate

Every script must pass before considering it done:

```bash
shellcheck -S warning script.sh   # static analysis
bash -n script.sh                 # syntax check (no shellcheck needed)
```

If `shellcheck` not installed: `apt install shellcheck` / `brew install shellcheck` / `scoop install shellcheck`.

## Shebang and strict mode

Always start scripts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `set -e`: exit on error
- `set -u`: exit on undefined variable (catches typos in var names)
- `set -o pipefail`: pipe fails if any command in pipe fails (not just last)
- `#!/usr/bin/env bash`: portable — works even if bash not in `/bin/bash`

## Variables

```bash
# Always quote variables
echo "$var"              # correct
echo $var                # wrong -- word splitting, glob expansion

# Declare intent explicitly
readonly CONFIG_FILE="/etc/app/config.json"
local result             # inside functions

# Default values
name="${1:-default}"
port="${PORT:-8080}"

# Arrays
files=("file1.txt" "file2.txt")
for f in "${files[@]}"; do  # always @, always quoted
    process "$f"
done
```

## Error handling

```bash
# Trap errors for cleanup
cleanup() {
    rm -f "$tmp_file"
}
trap cleanup EXIT

# Explicit error messages
die() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -f "$config" ] || die "Config file not found: $config"

# Check command availability
require() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed"
}
require jq
require curl
```

## Functions

```bash
# Declare with function keyword for clarity
function process_file() {
    local file="$1"
    local output="$2"

    [[ -f "$file" ]] || { echo "File not found: $file" >&2; return 1; }
    # ... logic ...
}
```

- `local` for all function variables — never pollute global scope
- Return 0 for success, non-zero for failure
- Document with a comment what the function expects

## Conditionals

```bash
# Use [[ ]] not [ ] for bash — more features, no word splitting issues
if [[ "$var" == "expected" ]]; then ...
if [[ -n "$var" ]]; then ...     # non-empty string
if [[ -z "$var" ]]; then ...     # empty string
if [[ -f "$path" ]]; then ...    # file exists
if [[ -d "$path" ]]; then ...    # dir exists

# Arithmetic
if (( count > 0 )); then ...
```

## Input/output

```bash
# Read stdin safely
while IFS= read -r line; do
    process "$line"
done < "$input_file"

# Temp files
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# stderr for errors/logs, stdout for data
echo "Processing..." >&2
echo "$result"   # stdout only for actual output
```

## Portability checklist

- No bashisms in scripts with `#!/bin/sh` shebang
- Avoid `echo -e` — use `printf` for escape sequences
- No process substitution `<()` in POSIX sh
- Test with `shellcheck -s sh` for POSIX compliance

## Script structure

```bash
#!/usr/bin/env bash
set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions
usage() {
    echo "Usage: $0 [options] <arg>" >&2
    exit 1
}

main() {
    [[ $# -ge 1 ]] || usage
    # ... logic ...
}

main "$@"
```

Always wrap logic in `main()` and call with `"$@"`.
