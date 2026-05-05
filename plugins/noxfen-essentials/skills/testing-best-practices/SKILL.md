---
name: testing-best-practices
description: >
  Testing best practices per language and test type. Activates when the user asks to
  "write tests", "add tests", "test this", mentions "unit test", "integration test",
  "coverage", "pytest", "cargo test", "vitest", "jest", or when working with test files
  (test_*.py, *_test.rs, *.test.ts, *.spec.ts). Apply alongside language-specific
  best practices skills.
version: 1.0.0
---

# Testing Best Practices

## What to test (and what not to)

**Test:**
- Behavior (what the function does) not implementation (how it does it)
- Edge cases: empty input, zero, null, max values, invalid input
- Error paths: what happens when things fail
- Boundary conditions: off-by-one, type boundaries

**Don't test:**
- Trivial getters/setters with no logic
- Third-party library behavior
- Private implementation details that can change
- Things that are better covered by type checking (TypeScript, Rust types)

## Test structure: Arrange-Act-Assert

```python
def test_parse_valid_config():
    # Arrange
    raw = '{"host": "localhost", "port": 8080}'

    # Act
    config = parse_config(raw)

    # Assert
    assert config.host == "localhost"
    assert config.port == 8080
```

One behavior per test. One reason to fail per test.

---

## Rust

```rust
// Unit tests: same file, cfg(test) module
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_add_positive_numbers() {
        assert_eq!(add(2, 3), 5);
    }

    #[test]
    fn test_add_negative_numbers() {
        assert_eq!(add(-1, -1), -2);
    }

    #[test]
    #[should_panic(expected = "division by zero")]
    fn test_divide_by_zero_panics() {
        divide(10, 0);
    }
}
```

```toml
# Cargo.toml -- add test dependencies
[dev-dependencies]
proptest = "1"        # property-based testing
insta = "1"           # snapshot testing
```

```bash
cargo test                          # all tests
cargo test test_add                 # filter by name
cargo test -- --nocapture           # show println! output
cargo test -- --test-threads=1      # serial (for tests with shared state)
```

**Property testing** (finds edge cases automatically):
```rust
use proptest::prelude::*;
proptest! {
    #[test]
    fn test_parse_roundtrip(s in "[a-z]{1,20}") {
        let encoded = encode(&s);
        assert_eq!(decode(&encoded), s);
    }
}
```

---

## Python

```python
# tests/test_parser.py
import pytest
from myapp.parser import parse

def test_parse_valid_input():
    assert parse("hello") == {"text": "hello"}

def test_parse_empty_raises():
    with pytest.raises(ValueError, match="empty input"):
        parse("")

@pytest.mark.parametrize("input,expected", [
    ("a", 1),
    ("ab", 2),
    ("abc", 3),
])
def test_length(input, expected):
    assert len(input) == expected
```

```bash
pip install pytest pytest-cov hypothesis

pytest                              # all tests
pytest tests/test_parser.py        # single file
pytest -k "parse"                  # filter by name
pytest --tb=short -q               # compact output
pytest --cov=myapp --cov-report=term-missing  # coverage
```

**Fixtures** for shared setup:
```python
@pytest.fixture
def db():
    conn = create_test_db()
    yield conn
    conn.close()

def test_insert(db):
    db.insert({"key": "val"})
    assert db.get("key") == "val"
```

**Property testing** with `hypothesis`:
```python
from hypothesis import given, strategies as st

@given(st.text())
def test_encode_decode_roundtrip(s):
    assert decode(encode(s)) == s
```

---

## JavaScript / TypeScript

```typescript
// vitest (preferred) or jest
import { describe, it, expect, vi } from "vitest";
import { processData } from "./processor";

describe("processData", () => {
  it("returns empty array for empty input", () => {
    expect(processData([])).toEqual([]);
  });

  it("throws on invalid input", () => {
    expect(() => processData(null as any)).toThrow("invalid input");
  });

  it("calls transform for each item", () => {
    const transform = vi.fn((x: number) => x * 2);
    processData([1, 2, 3], transform);
    expect(transform).toHaveBeenCalledTimes(3);
  });
});
```

```bash
npm install -D vitest @vitest/coverage-v8

npx vitest run              # run once
npx vitest                  # watch mode
npx vitest run --coverage   # with coverage
```

**React component testing**:
```typescript
import { render, screen, fireEvent } from "@testing-library/react";

it("shows error on invalid email", async () => {
  render(<LoginForm />);
  fireEvent.change(screen.getByLabelText("Email"), { target: { value: "bad" } });
  fireEvent.click(screen.getByRole("button", { name: "Login" }));
  expect(await screen.findByText("Invalid email")).toBeInTheDocument();
});
```

---

## C

No stdlib test framework — use `Unity` or `Check`:

```c
// test_parser.c
#include "unity.h"
#include "parser.h"

void setUp(void) {}
void tearDown(void) {}

void test_parse_valid_returns_ok(void) {
    Result r = parse("hello");
    TEST_ASSERT_EQUAL(OK, r.status);
    TEST_ASSERT_EQUAL_STRING("hello", r.value);
}

void test_parse_empty_returns_error(void) {
    Result r = parse("");
    TEST_ASSERT_EQUAL(ERR_EMPTY, r.status);
}

int main(void) {
    UNITY_BEGIN();
    RUN_TEST(test_parse_valid_returns_ok);
    RUN_TEST(test_parse_empty_returns_error);
    return UNITY_END();
}
```

```makefile
test: test_parser
    ./test_parser

test_parser: test_parser.c parser.c unity/unity.c
    gcc -Iunity -Wall -Wextra -o test_parser test_parser.c parser.c unity/unity.c
```

Use `-fsanitize=address,undefined` in test builds to catch memory errors during tests.

---

## Bash

Use `bats-core`:
```bash
# test_script.bats
@test "script outputs hello" {
  run ./myscript.sh
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "script fails on missing arg" {
  run ./myscript.sh
  [ "$status" -ne 0 ]
}
```

```bash
npm install -g bats   # or: apt install bats
bats test_script.bats
```
