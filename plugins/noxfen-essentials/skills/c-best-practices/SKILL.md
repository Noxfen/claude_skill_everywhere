---
name: c-best-practices
description: >
  C programming best practices focused on memory safety, undefined behavior, and correctness.
  Activates when working with .c or .h files, or when the user asks to "write C", "C code",
  "C function", "C programming", mentions gcc/clang/valgrind/sanitizers, or discusses C patterns.
  Enforces safe, portable, production-quality C (C99/C11).
version: 1.0.0
---

# C Best Practices

Apply these rules whenever writing or reviewing C code.

## Compilation flags (mandatory)

Always compile with:

```bash
# Development / debug build
gcc -std=c11 -Wall -Wextra -Werror -pedantic \
    -fsanitize=address,undefined \
    -g -O1 \
    -o program program.c

# Release build
gcc -std=c11 -Wall -Wextra -Werror -pedantic \
    -O2 \
    -o program program.c
```

- `-Wall -Wextra -Werror`: all warnings + treat as errors
- `-pedantic`: strict standard compliance
- `-fsanitize=address,undefined`: catch memory errors and UB at runtime (debug builds)

If using clang: same flags apply. Prefer clang for better diagnostics.

## Static analysis

```bash
clang-tidy program.c -- -std=c11          # static analysis
cppcheck --enable=all --std=c11 program.c  # complementary checker
```

Fix all warnings from both tools before considering code done.

## Memory management

Every `malloc`/`calloc`/`realloc` must have a matching `free`:

```c
// Pattern: allocate, check, use, free
char *buf = malloc(size);
if (buf == NULL) {
    perror("malloc");
    return ERROR_OOM;
}
// ... use buf ...
free(buf);
buf = NULL;   // poison the pointer after free
```

Rules:
- Check return value of `malloc`/`calloc` for NULL — always
- Set pointers to `NULL` after `free` to catch use-after-free
- Ownership must be clear: who allocates owns the object, or document the transfer explicitly
- Use `valgrind --leak-check=full` before release: `valgrind ./program`

## Forbidden functions

Never use:
- `gets()` — use `fgets()` with explicit size
- `sprintf()` without bounds — use `snprintf(buf, sizeof(buf), ...)`
- `strcpy()` / `strcat()` — use `strncpy()` / `strncat()` or `strlcpy()` / `strlcat()` (where available)
- `scanf("%s", ...)` without width — use `scanf("%255s", buf)` or `fgets()`

## Undefined behavior — avoid completely

- **Array out of bounds**: always check indices
- **Signed integer overflow**: use `unsigned` for wrapping arithmetic, or check before operating
- **Null pointer dereference**: validate pointers before use
- **Use after free**: poison pointers after `free`
- **Uninitialized reads**: initialize all variables at declaration
- **Strict aliasing violations**: don't cast `int*` to `float*` etc.

```c
// Bad — uninitialized
int x;
printf("%d\n", x);  // UB

// Good
int x = 0;
```

## Formatting

Use `clang-format` for consistent style:

```bash
clang-format -i -style=LLVM program.c   # or: -style=GNU, -style=Google
```

Add `.clang-format` to the project root to enforce style across the team.

## Header guards

```c
#pragma once   // preferred (supported by all modern compilers)

// Or the traditional form:
#ifndef MYPROJECT_FOO_H
#define MYPROJECT_FOO_H
// ... declarations ...
#endif /* MYPROJECT_FOO_H */
```

Never include `.c` files — only `.h` files.

## No VLAs

Variable-length arrays (VLAs) were optional in C11 and are error-prone:

```c
// Bad — VLA
void process(int n) {
    int buf[n];  // stack size unknown at compile time
}

// Good — dynamic allocation with checked size
void process(int n) {
    if (n <= 0 || n > MAX_SIZE) return;
    int *buf = calloc(n, sizeof(int));
    if (!buf) { /* handle */ return; }
    // ...
    free(buf);
}
```

## Structure and modularity

```
project/
  include/
    mylib.h      # public API
  src/
    mylib.c      # implementation
    internal.h   # private declarations
  tests/
    test_mylib.c
  Makefile
```

- Public API in `include/`, private in `src/`
- One `.c` file per logical module
- Use `static` for functions not part of the public API (limits linkage)
