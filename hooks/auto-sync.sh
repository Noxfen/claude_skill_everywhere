#!/usr/bin/env bash
# SessionStart hook — auto-pulls claude_skill_everywhere checkouts to stay in sync
# Install: bash hooks/install.sh (registered automatically)
#
# Checks every known location instead of a single hardcoded default: the old
# version only looked at $HOME/claude_skill_everywhere, which does not exist on
# a machine that clones the repo elsewhere (e.g. D:\dev), so the hook silently
# exited 0 forever. Set CLAUDE_SKILL_EVERYWHERE_DIR to add your dev checkout.

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

CANDIDATES=(
  "${CLAUDE_SKILL_EVERYWHERE_DIR:-}"
  "$CLAUDE_DIR/plugins/marketplaces/Noxfen-claude_skill_everywhere"
  "$HOME/claude_skill_everywhere"
)

updated=""
seen=""

for dir in "${CANDIDATES[@]}"; do
  [ -n "$dir" ] || continue
  # Linked worktrees have a .git FILE, not a directory -- ask git itself.
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || continue

  # Deduplicate: the same checkout may be reachable by several of the paths above
  real=$(cd "$dir" 2>/dev/null && pwd -P) || continue
  case "$seen" in *"|$real|"*) continue ;; esac
  seen="$seen|$real|"

  # Compare HEAD before/after rather than parsing output: `pull --quiet` prints
  # nothing on a successful fast-forward, so the old output test never fired.
  before=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || continue
  git -C "$dir" pull --ff-only --quiet >/dev/null 2>&1 || continue
  after=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || continue

  if [ "$before" != "$after" ]; then
    updated="$updated $dir"
  fi
done

if [ -n "$updated" ]; then
  echo "[claude_skill_everywhere] Updated from remote:$updated"
fi

exit 0
