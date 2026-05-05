---
name: js-best-practices
description: >
  JavaScript and TypeScript best practices. Activates when working with .js, .ts, .jsx, .tsx
  files, or when the user asks to "write javascript", "write typescript", "node.js", "react
  component", "refactor JS", mentions eslint/prettier/bun/vite, or discusses JS/TS patterns.
  Enforces typed, idiomatic, production-quality TypeScript.
version: 1.0.0
---

# JavaScript / TypeScript Best Practices

Default to TypeScript. Apply these rules whenever writing or reviewing JS/TS code.

## Quality gates

```bash
prettier --write <file>     # formatting
eslint --fix <file>         # linting + auto-fix
tsc --noEmit               # type checking (project-wide)
```

Both tools must be configured in the project (`prettier.config.*`, `eslint.config.*`, `tsconfig.json`).
If they're not set up, offer to add them before writing code.

## TypeScript always

- Use `.ts` / `.tsx` — never `.js` for new files unless interoperating with legacy code
- `tsconfig.json` must have `"strict": true`
- `"noUncheckedIndexedAccess": true` — prevents silent undefined from array/object access

## No `any`

```typescript
// Bad
function process(data: any): any { ... }

// Good — use unknown + type guard
function process(data: unknown): string {
  if (typeof data !== "string") throw new TypeError("Expected string");
  return data.trim();
}
```

- `any` disables type checking entirely — use `unknown` and narrow with guards
- `as SomeType` casts: only when you have proof the type is correct (e.g., after a parse)
- Prefer `satisfies` over `as` for object literals

## Async / await

```typescript
// Bad — .then() chains
fetch(url)
  .then(r => r.json())
  .then(data => process(data))
  .catch(handleError);

// Good — async/await
async function loadData(url: string): Promise<Data> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json() as Promise<Data>;
}
```

- Always `async/await` — no `.then()` chains
- Handle rejections: `try/catch` in async functions or `.catch()` at the top call site
- Never `await` in a loop when calls are independent — use `Promise.all()`

## Error handling

```typescript
try {
  const result = await riskyOperation();
} catch (err) {
  if (err instanceof NetworkError) {
    // handle network error
  } else if (err instanceof Error) {
    logger.error(err.message, { stack: err.stack });
  } else {
    throw err; // re-throw unknown
  }
}
```

- Catch and check `instanceof Error` before accessing `.message`
- Define custom error classes (`class MyError extends Error`)
- Never swallow errors silently

## Imports

```typescript
// Named imports preferred over default
import { parseDate, formatDate } from "./utils/date";

// Type-only import (erased at compile time)
import type { User } from "./types";
```

- Named imports over default where possible (better tree-shaking + renaming clarity)
- `import type` for type-only imports (required with `isolatedModules`)
- Avoid barrel files (`index.ts` that re-exports everything) — they hurt tree-shaking

## React (when applicable)

```typescript
// Functional component with typed props
interface ButtonProps {
  label: string;
  onClick: () => void;
  disabled?: boolean;
}

export function Button({ label, onClick, disabled = false }: ButtonProps) {
  return <button onClick={onClick} disabled={disabled}>{label}</button>;
}
```

- Functional components + hooks only — no class components
- Type all props with interfaces, not `React.FC<Props>` (which hides return type)
- `useCallback` / `useMemo` only when profiling proves render cost — don't premature-optimize

## Null / undefined

- Use `??` (nullish coalescing) not `||` for defaults (avoids false-y short-circuit on 0 / "")
- Optional chaining `?.` to safely access nested properties
- Avoid `null` in new code — prefer `undefined` (more idiomatic JS, simpler union types)

## Module / project structure

```
src/
  components/     # React components
  hooks/          # Custom React hooks
  services/       # API calls, external integrations
  utils/          # Pure utility functions
  types/          # Shared type definitions
  index.ts        # Entry point
```
