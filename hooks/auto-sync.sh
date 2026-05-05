#!/usr/bin/env bash
# SessionStart hook — auto-pulls claude_skill_everywhere repo to stay in sync
# Install: bash hooks/install.sh (registered automatically)

REPO_DIR="${CLAUDE_SKILL_EVERYWHERE_DIR:-$HOME/claude_skill_everywhere}"

[ -d "$REPO_DIR/.git" ] || exit 0

output=$(git -C "$REPO_DIR" pull --ff-only --quiet 2>&1) || exit 0

if [ -n "$output" ] && ! echo "$output" | grep -q "Already up to date"; then
  echo "[claude_skill_everywhere] Updated from remote. New skills/hooks available."
fi

exit 0
