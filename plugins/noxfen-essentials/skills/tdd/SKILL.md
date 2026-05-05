---
name: tdd
description: >
  Test-Driven Development workflow. Activates when the user says "TDD", "test driven",
  "write tests first", "red green refactor", "write a failing test", "make this test pass",
  or when implementing a new feature that should have tests. Enforces the
  Red-Green-Refactor cycle: write failing test first, then implement, then refactor.
version: 1.0.0
---

# Test-Driven Development (TDD)

TDD means writing the test BEFORE the implementation. Not after. Not at the same time.

## The cycle (non-negotiable)

```
RED   → Write a test that fails (the feature doesn't exist yet)
GREEN → Write the minimum code to make the test pass
REFACTOR → Clean up the code while keeping the test green
```

Repeat for every new behavior.

## Step 1 — RED: write the failing test

Write a test that describes the desired behavior. Run it. It must fail.

```rust
// Rust example — this fails because add() doesn't exist yet
#[test]
fn test_add_two_positive_numbers() {
    assert_eq!(add(2, 3), 5);
}
```

```python
# Python — this fails because process() doesn't exist yet
def test_process_empty_input_returns_empty():
    assert process([]) == []
```

**If the test passes before you write any code, the test is wrong.**  
Delete it and write a better one.

## Step 2 — GREEN: minimum implementation

Write the *simplest possible code* that makes the test pass. No more.

- If hardcoding the return value makes it pass → hardcode it first
- Add more tests to force a real implementation
- Do NOT add features not yet covered by a failing test

## Step 3 — REFACTOR: clean without breaking

With tests green:
- Remove duplication
- Rename for clarity
- Extract functions/modules
- Improve error handling

Run tests after every change. If anything breaks, revert immediately.

## When to apply TDD

**Apply TDD when:**
- Building new features with clear inputs/outputs
- Fixing bugs (write a test that reproduces the bug first, then fix)
- Implementing algorithms or business logic
- Building parsers, validators, transformers

**Skip TDD when:**
- Pure exploration/spike (throw it away after)
- One-shot scripts with no reuse
- UI layout code (hard to test meaningfully)
- Glue code that just wires existing components

## Common mistakes

- Writing the implementation before the test ("I'll add tests later") → don't
- Writing multiple tests before any implementation → go one test at a time
- Testing implementation details instead of behavior → test what it does, not how
- Green tests that don't actually verify the behavior → assert real values

## Test granularity

- One test = one behavior, one assertion (or a few tightly related)
- Test name describes the scenario: `test_<function>_<condition>_<expected>`
- Example: `test_parse_empty_string_returns_error`, not `test_parse`
