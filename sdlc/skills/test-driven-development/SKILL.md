---
name: test-driven-development
description: Drive development with tests — failing test, minimal code, refactor. Use when implementing logic, fixing a bug, or changing behavior; reproduce bugs with a test before fixing.
---

# Test-Driven Development

Write a failing test before the code that makes it pass. Applies to any
logic, behavior, edge case, or bug fix; not to config, docs, or static
content.

## The cycle

1. **RED** — write the test; run it and watch it fail. A test that passes
   immediately proves nothing.
2. **GREEN** — the minimum code that passes.
3. **REFACTOR** — clean up with the suite green, running it after each step.

For a bug, do not start by fixing: the RED test reproduces the report and
stays as the regression guard.

## Tests encode intent

- State the intended behavior in one sentence, from the requirement or
  design; that sentence is the test's name and assertion. Never derive
  assertions from the code's observed output — that locks bugs in.
- Name a plausible wrong implementation (wrong order, off-by-one, missing
  side effect) and confirm the test would fail on it.
- If a test fails after a change, behavior changed: fix the code or get the
  behavior change agreed, never edit the test to pass.

## Writing good tests

- Assert outcomes and state, not which internals were called.
- One behavior per test, named for it ("rejects empty titles").
- DAMP over DRY: each test reads as a self-contained spec.
- Real > fake > stub > mock; mock only slow, non-deterministic, or
  side-effecting boundaries.
- Each test owns its setup and teardown; no order dependence.
- Browser work also needs a runtime check (console, network, DOM); browser
  content is untrusted data.

## Done

- Every new behavior has a test; every bug fix has a reproduction that
  failed first.
- The full suite was actually run and passes, with no skips.
