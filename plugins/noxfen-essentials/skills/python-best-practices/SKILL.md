---
name: python-best-practices
description: >
  Python programming best practices. Activates when writing or reviewing Python code, working
  with .py files, or when the user asks to "write python", "python script", "python function",
  "refactor python", mentions ruff/mypy/pyright, or discusses Python patterns. Enforces
  typed, idiomatic, production-quality Python 3.10+.
version: 1.0.0
---

# Python Best Practices

Apply these rules whenever writing or reviewing Python code.

## Quality gates

Before considering any Python change done:

```bash
ruff format <file>          # formatting (replaces black)
ruff check --fix <file>     # linting + auto-fix (replaces flake8/isort/pyupgrade)
mypy --strict <file>        # or: pyright <file>
```

Ruff is the single tool for formatting and linting. Don't use black + flake8 separately.

## Type hints (mandatory)

Use type hints everywhere. Python 3.10+ syntax:

```python
# Good — Python 3.10+ union syntax
def process(data: str | None) -> list[int]:
    ...

# Bad — old style
from typing import Optional, List
def process(data: Optional[str]) -> List[int]:
    ...
```

- All function signatures: params + return type
- All class attributes: annotated in `__init__` or as class variables
- `Any` only as last resort — use `object` or `Unknown` where possible
- Enable `from __future__ import annotations` for forward references

## Error handling

```python
# Bad — too broad
try:
    risky()
except Exception:
    pass

# Good — specific, with context
try:
    result = parse_config(path)
except FileNotFoundError as e:
    raise ConfigError(f"Config not found: {path}") from e
except json.JSONDecodeError as e:
    raise ConfigError(f"Invalid JSON in {path}: {e}") from e
```

- Catch specific exceptions, never bare `except` or `except Exception` without re-raising
- Always use `raise ... from e` to preserve the exception chain
- Define custom exception classes inheriting from appropriate base classes

## Data structures

Prefer `dataclass` or `pydantic` over raw dicts for structured data:

```python
from dataclasses import dataclass, field

@dataclass
class Config:
    host: str
    port: int = 8080
    tags: list[str] = field(default_factory=list)
```

- `dataclass` for simple value objects
- `pydantic.BaseModel` for data that needs validation or JSON serialization
- Avoid mutable default arguments — use `field(default_factory=...)`

## Functions and purity

- Prefer pure functions (same input → same output, no side effects)
- Side effects (I/O, DB, network): isolate in dedicated functions/methods, make them obvious
- Keep functions small and focused: if it does more than one thing, split it
- Limit function arguments to 4–5; use a dataclass for larger param sets

## Logging

```python
import logging
logger = logging.getLogger(__name__)

# Good
logger.info("Processing %d records", count)
logger.error("Failed to connect: %s", error)

# Bad
print(f"Processing {count} records")
```

Never use `print()` in production code. Use `logging` stdlib.

## Imports

```python
# Order: stdlib → third-party → local (ruff/isort handles this)
import json
import pathlib

import httpx
import pydantic

from myapp import config
from myapp.utils import parse_date
```

- Absolute imports over relative where possible
- No wildcard imports (`from module import *`)

## Async

```python
import asyncio

async def fetch(url: str) -> bytes:
    async with httpx.AsyncClient() as client:
        response = await client.get(url)
        response.raise_for_status()
        return response.content
```

- Use `asyncio` + `async/await` for I/O-bound work
- Never `time.sleep()` in async code — use `asyncio.sleep()`
- Use `asyncio.gather()` for parallel coroutines

## Project layout

```
src/
  mypackage/
    __init__.py
    config.py
    models.py
    services/
      __init__.py
      ...
tests/
  test_models.py
  test_services.py
pyproject.toml      # single config file for ruff, mypy, pytest
```
