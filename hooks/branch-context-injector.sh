#!/usr/bin/env bash
# UserPromptSubmit hook -- inject terse git status into every prompt
# Output goes to stdout, gets appended to user's prompt as additional context.
# Skips silently if not in a git repo or if disabled via CLAUDE_NO_GIT_CTX=1.

[ "${CLAUDE_NO_GIT_CTX:-0}" = "1" ] && exit 0

json=$(cat)
workdir=$(echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)
[ -z "$workdir" ] && workdir="$PWD"
[ ! -d "$workdir" ] && exit 0

branch=$(git -C "$workdir" branch --show-current 2>/dev/null) || exit 0
[ -z "$branch" ] && exit 0

status=$(git -C "$workdir" status --porcelain 2>/dev/null)
modified=0
untracked=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [[ "$line" == \?\?* ]]; then
        untracked=$((untracked + 1))
    else
        modified=$((modified + 1))
    fi
done <<< "$status"

out="git: $branch"
[ "$modified"  -gt 0 ] && out="$out | $modified modified"
[ "$untracked" -gt 0 ] && out="$out | $untracked untracked"

echo "[$out]"
exit 0
