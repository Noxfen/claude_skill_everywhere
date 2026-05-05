---
name: orchestrator
description: >
  Multi-agent task orchestration skill. Use when the user asks to "orchestrate", "spawn agents",
  "parallelize this", "plan with subagents", "break this into agents", or when a task is clearly
  complex enough to benefit from parallel subagents (large refactors, multi-module features,
  cross-cutting analysis). Also triggers on "/orchestrate" or "/swarm".
  Analyzes complexity, token budget, and routes work to the right models to minimize cost.
version: 1.0.0
---

# Orchestrator

Decompose complex tasks into parallel subagent workstreams. Route each workstream to the cheapest
model that can handle it. Synthesize results in the main context.

## Step 1 — Complexity Assessment

Before spawning anything, classify the task:

| Level | Criteria | Action |
|-------|----------|--------|
| **Simple** | Single file, clear scope, <200 lines affected | Do it directly, no agents |
| **Medium** | 2–5 files, clear interfaces, isolated changes | 1–2 agents max |
| **Complex** | Cross-cutting, >5 files, multiple concerns | 3–5 specialized agents |
| **Massive** | Full feature, architectural change, >10 modules | Phase into waves; first wave scopes, second executes |

If Simple → stop here and do the task directly.

## Step 2 — Token Budget Check

Estimate token cost before spawning:
- Each subagent spawns a fresh context (~2K tokens overhead)
- Research agents: ~10K–30K tokens each
- Implementation agents: ~30K–100K tokens each
- If total estimate exceeds available budget, reduce agent count or scope

Current model costs (relative, as of 2026):
- **Haiku 4.5**: cheapest, fast — use for search, grep, file listing, simple transforms
- **Sonnet 4.6**: balanced — use for implementation, refactoring, moderate reasoning
- **Opus 4.7**: most capable, expensive — use for architecture, complex reasoning, final synthesis

Rule: 80% of token work should land on Haiku/Sonnet. Opus only for what truly needs it.

## Step 3 — Workstream Design

Decompose the task into independent workstreams. Each must be:
- **Self-contained**: agent can complete it without coordinating with siblings
- **Well-bounded**: clear input, clear expected output
- **Appropriately sized**: not so small that overhead dominates, not so large it needs sub-decomposition

### Standard agent roles

**Explorer** (Haiku): Read-only codebase analysis. Find files, grep symbols, map dependencies.
Prompt pattern: "Search X in codebase. Report: file paths, line numbers, relevant snippets. No edits."

**Implementer** (Sonnet): Write/edit code for a single bounded module or concern.
Prompt pattern: "Implement X in files [list]. Context: [what explorer found]. Return: diff summary."

**Reviewer** (Sonnet): Check a completed implementation for correctness, edge cases, consistency.
Prompt pattern: "Review [what implementer did]. Check: [specific concerns]. Report issues or OK."

**Architect** (Opus): Only for genuinely ambiguous design decisions or cross-cutting concerns.
Use sparingly — one per session max unless budget is large.

## Step 4 — Spawn & Collect

Spawn all independent agents in a single message (parallel). For dependent workstreams, wait
for upstream agents before spawning downstream ones.

Before spawning, state the plan to the user:
```
Orchestrating N agents:
  [Agent 1] Explorer → [scope] (Haiku)
  [Agent 2] Implementer → [module A] (Sonnet)
  [Agent 3] Implementer → [module B] (Sonnet)
Estimated tokens: ~Xk. Proceed? [y/n]
```

Wait for user confirmation before spawning if total estimated cost exceeds 100K tokens.

## Step 5 — Synthesis

After all agents complete:
1. Summarize what each agent did (1 line each)
2. Identify any conflicts or gaps between workstreams
3. Apply any necessary integration fixes in the main context
4. Report total: files changed, tokens used (approximate)

## Context efficiency (critical for long sessions)

Main context is the scarcest resource. Every byte the orchestrator adds persists for the entire session.

**When prompting each subagent, always end with:**
```
Report in max 200 words: what changed, what issues found, what to do next.
No reasoning chain. No code blocks unless the exact code is the answer.
```

**When collecting results:**
- Synthesize each agent result in 1-3 lines before adding to main context
- Never copy-paste the full agent response — extract only actionable findings
- If agent output >50 lines: summarize in 5 lines, note "full output available on request"
- Never repeat back the prompt you gave the agent

**If context estimate (from statusline `ctx %~`) approaches 70%:**
- Reduce number of agents in next wave
- Ask agents for even more compressed output
- Consider running `/compact` before the next major task

**Anti-patterns:**
- Pasting full stack traces into main context (summarize: "N errors, top issue: X")
- Repeating agent inputs in synthesis ("I asked agent 1 to do X, and it did X...")
- Spawning agents whose combined output will exceed remaining context budget

## Anti-patterns to avoid

- Spawning agents for tasks you can do in <30 seconds directly
- Making agents depend on each other in complex chains (flattens parallelism)
- Using Opus when Sonnet suffices (3x cost for marginal gain)
- Spawning more than 5 agents without user confirmation
- Agents that write to overlapping files simultaneously (race condition)
