---
name: debug
description: >
  Systematic debugging methodology. Use when the user reports a bug, unexpected behavior,
  test failure, compilation error, or runtime error. Activates on "debug this", "why is X
  happening", "this is broken", "fix this error", error messages pasted into chat, or
  stack traces. Avoids random-change debugging in favor of hypothesis-driven investigation.
version: 1.0.0
---

# Debug

Systematic diagnosis before fixes. Never change code to "try something" without a hypothesis.

## The method

### 1. Reproduce

First: can you reproduce the problem reliably?
- If yes: note exact conditions (input, state, environment)
- If flaky: note frequency and any pattern (timing, concurrency, input size)
- If can't reproduce: ask the user for exact steps before proceeding

Don't touch code until you can reproduce or have the user's repro steps.

### 2. Locate

Narrow to the smallest failing unit:
- Read the error message exactly — don't paraphrase it, quote it
- Follow the stack trace from top (immediate cause) to root (actual bug)
- Use grep/search to find the relevant code before reading it
- Identify the boundary where correct behavior becomes incorrect

Common traps:
- The error location ≠ the bug location (symptom vs cause)
- Null/undefined errors often originate several frames above where they surface
- Type errors often mean a wrong assumption about a function's return type

### 3. Hypothesize

Form 1–3 hypotheses ranked by likelihood. For each:
- State what would be true if this hypothesis is correct
- State how to verify it (what to read, what to log, what to test)

Don't write any fix yet.

### 4. Verify

Test the top hypothesis first. Methods:
- Read the relevant code (often enough)
- Add a temporary log/print (note: temporary, remove after)
- Write a minimal failing test that isolates the bug
- Check git blame to see when the behavior changed

Eliminate hypotheses systematically. Update ranking as evidence comes in.

### 5. Fix

Once root cause is confirmed:
- Fix the cause, not the symptom
- Check for similar bugs elsewhere (grep for the pattern)
- Write/update a test that would have caught this bug
- Remove any temporary logging

### 6. Verify fix

After fixing:
- Confirm the original reproduction no longer fails
- Run the full test suite if available
- Check that no related behavior regressed

## Common bug patterns

**Off-by-one**: check loop bounds, slice indices, fence-post conditions  
**Race condition**: look for shared mutable state accessed across goroutines/threads/async  
**Null/nil dereference**: trace where the value is set; find the code path that skips initialization  
**Wrong type/unit**: check what the function actually returns vs what callers assume  
**Stale cache/state**: check if the bug disappears on restart or with cleared state  
**Wrong assumption about external API**: read the actual API docs/source, don't trust memory
