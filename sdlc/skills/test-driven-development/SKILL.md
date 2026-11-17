---
name: test-driven-development
description: Drive development with tests — a failing test first, the minimal code to pass it, then refactor. Use for any logic or behavior change, and to reproduce a bug before fixing it.
---

# Test-Driven Development

Write the failing test before the code that makes it pass. Tests are proof;
"seems right" is not done.

## When

- Any new or changed logic or behavior
- Any bug fix — reproduce it first
- Edge cases and error paths, as they are the ones that regress

Not for pure config, docs or static content with no behavioral surface.
Changes like those are verified by the repo's own checks instead.

## The cycle

```
RED                  GREEN                  REFACTOR
write a test      -> minimal code        -> clean up while
that FAILS           that passes it         tests stay green
```

1. **RED** — write the test first and run it. It must fail for the right
   reason. A test that passes immediately proves nothing: either the behavior
   already exists or the test does not exercise it.
2. **GREEN** — the minimum code that passes. Do not build what the test does
   not demand; the test defines done.
3. **REFACTOR** — with the suite green, improve names, remove duplication,
   flatten indirection. Run the tests after each small step.

## Prove-It for bugs

Given a bug report: write a test that fails on the current tree and names the
bug in its own words, fix until it passes, then keep the test as the
regression guard. Without that test you have a guess followed by an edit.

## Tests encode intent

A test states **intended** behavior, derived from the request, the design or
the issue — never a recording of what the code currently does. That is why it
is written first: it must be able to disagree with the implementation.

- One behavior per test, named for the behavior (`test_approve_requires_yes_in_pipeline`),
  not for the function.
- Assert on observable behavior, not private internals.
- Keep the test data minimal and inline; a fixture nobody reads hides what
  the case is about.
- Failure messages should say what broke, so CI output alone is actionable.

## In this repo

Python stdlib `unittest`, discovered from `tests/`:

```sh
uv run --python 3.12 python -m unittest discover -s tests -v
```

Single file or case while iterating:

```sh
uv run --python 3.12 python -m unittest tests.test_skills -v
```

Match the neighbors' style: stdlib only, a fake on `PATH` instead of a network
call, `setUp`/`tearDown` that leave no state behind. The same suite runs in CI
on 3.11 and 3.12.

## Done means

- The new test failed before the change and passes after.
- The whole suite passes, not just the new test.
- No test was weakened, skipped or deleted to get there.
