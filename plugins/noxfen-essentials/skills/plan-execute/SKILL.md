---
name: plan-execute
description: >
  Structured planning before execution for non-trivial tasks. Use when the task involves
  multiple files, architectural decisions, or unclear scope. Activates on "/plan", "think before
  doing", "plan this out", "what's the approach", "how should we tackle", or when the user
  asks for a plan before implementation. Prevents costly wrong-direction work.
version: 1.0.0
---

# Plan-Execute

Think before writing code. For non-trivial tasks: explore → plan → confirm → execute.

## When to apply

Apply this skill when:
- Task touches >3 files or >1 module
- Scope is unclear or multiple approaches exist
- Architectural decisions need to be made
- The wrong approach would require significant rework

Skip for: typo fixes, single-line changes, clearly specified one-file edits.

## Phase 1 — Explore (Read-only)

Before planning, gather facts:
1. Read relevant files (don't guess at structure)
2. Find existing patterns to reuse (grep for similar implementations)
3. Identify constraints (tests that must pass, APIs that must stay stable)
4. Note what's already done vs what's missing

Output: a factual summary, not proposals. "File X does Y. Pattern Z is used in A and B."

## Phase 2 — Plan

Write a concrete plan:
- List files to modify (exact paths)
- For each file: what changes and why
- Identify the riskiest change (most likely to break things)
- State any assumptions that could be wrong

Format:
```
Files:
  src/foo.rs — add method bar() to handle X
  src/main.rs — wire foo into startup

Approach: [1-2 sentences on the core technique]
Risk: [what could go wrong]
Assumption: [what you're assuming about X]
```

## Phase 3 — Confirm

Present the plan to the user before writing any code. Keep it scannable:
- No walls of text
- Bullet points, not paragraphs
- Highlight the risky parts

Wait for explicit confirmation ("yes", "go", "do it") or revision requests.

## Phase 4 — Execute

Execute exactly the confirmed plan. If you discover something unexpected mid-execution
that changes the approach, stop and report — don't silently pivot.

After execution: verify the change works (run tests if available, check compilation).
