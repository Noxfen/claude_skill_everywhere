---
name: rust-best-practices
description: >
  Rust programming best practices. Activates when writing or reviewing Rust code, working with
  .rs files, discussing Rust patterns, or when the user asks to "write rust", "refactor rust",
  "rust error handling", "rust async", or mentions cargo/clippy/rustfmt. Enforces idiomatic,
  safe, production-quality Rust.
version: 1.0.0
---

# Rust Best Practices

Apply these rules whenever writing or reviewing Rust code.

## Quality gates (non-negotiable)

Every Rust code change must pass before considering it done:

```bash
cargo fmt                                              # formatting
cargo clippy --all-targets --all-features -- -D warnings  # linting, treat warnings as errors
cargo test                                             # all tests green
```

If clippy emits a warning, fix the code — don't `#[allow(...)]` unless there's a documented,
specific reason why the lint is a false positive for this exact case.

## Error handling

| Context | Tool |
|---------|------|
| Binary / application | `anyhow::Result<T>` — ergonomic, context-rich |
| Library | `thiserror` — typed errors, stable API |
| Internal logic | `Option<T>` — for absence, not for errors |

**Never** use `unwrap()` or `expect()` in production paths. Use `?` to propagate.  
Exception: tests and examples may use `unwrap()`. If you must `expect()`, the string must explain
*why* this can't fail, not just *what* failed.

```rust
// Bad
let val = map.get("key").unwrap();

// Good
let val = map.get("key").ok_or_else(|| anyhow!("key missing from config"))?;
```

## Project layout

```
src/
  main.rs        # binary entry point — thin, delegates to lib
  lib.rs         # library root — pub API surface
  error.rs       # error types (thiserror)
  config.rs      # configuration structs
  <feature>/
    mod.rs
    ...
tests/           # integration tests (test the public API)
benches/         # criterion benchmarks
examples/        # runnable examples
```

## Ownership and lifetimes

- Prefer **owned types** unless profiling proves the clone is a bottleneck
- Lifetimes in public APIs: hide them with `Arc<T>` or owned types when possible
- `Rc<T>` only for single-threaded; `Arc<T>` for shared ownership across threads
- `Cell<T>` / `RefCell<T>`: acceptable in limited internal contexts, document why

## Unsafe

- Every `unsafe` block needs a `// SAFETY:` comment explaining the invariant maintained
- Minimize the surface: isolate unsafe in a single module behind a safe API
- Test with `cargo miri test` before merging any unsafe code

## Async

- Standard runtime: `tokio` with `#[tokio::main]`
- Never call `std::thread::sleep` inside async code — use `tokio::time::sleep`
- Avoid `block_on` inside async contexts
- Prefer `tokio::spawn` for independent tasks; use `JoinSet` for structured concurrency
- Pin futures explicitly only when required (`Box::pin` or `pin!` macro)

## Performance

- Profile before optimizing (`cargo flamegraph`, `criterion`)
- Use `sccache` for faster incremental builds in CI
- `--release` for benchmarks, debug for development
- Avoid premature allocation: prefer `&str` over `String` in function params when not storing

## Modules and visibility

- Keep `pub` surface minimal — use `pub(crate)` for internal sharing
- One module per file for non-trivial modules
- Re-export selectively in `lib.rs` — don't expose internal types

## Testing

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_name_describes_scenario() {
        // arrange
        // act
        // assert
    }
}
```

- Unit tests: in the same file as the code under test, in `#[cfg(test)]` module
- Integration tests: in `tests/`, test the public API as an external consumer would
- Property tests: use `proptest` or `quickcheck` for parsing/serialization logic
