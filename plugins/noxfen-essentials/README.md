# noxfen-essentials

Personal Claude Code plugin by Noxfen. Best-practice skills, auto-loaded by Claude when the skill's trigger conditions match.

## Install

```
/plugin install noxfen-essentials@noxfen
```

Or via the marketplace installer — see the [repo root README](../../README.md).

## Skills

| Skill | Triggers on |
|-------|-------------|
| `rust-best-practices` | `.rs` files, cargo/clippy/rustfmt |
| `python-best-practices` | `.py` files, ruff/mypy/pyright |
| `js-best-practices` | `.js/.ts/.jsx/.tsx`, eslint/prettier/node |
| `c-best-practices` | `.c/.h` files, gcc/clang/valgrind/sanitizers |
| `bash-best-practices` | `.sh` files, shellcheck |
| `powershell-best-practices` | `.ps1/.psm1/.psd1`, PSScriptAnalyzer |
| `testing-best-practices` | writing tests: pytest/cargo test/vitest/jest |

Methodology skills (planning, TDD, debugging, orchestration, code review) are intentionally **not** here — they are covered by the official `superpowers` plugin and the native Workflow tool to avoid double-triggering.
