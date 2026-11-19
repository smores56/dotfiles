---
name: grill-me
description: Interrogate a plan or design one decision at a time until aligned. Use to stress-test a plan before building. Triggers "grill me", "interrogate this plan", "stress-test this design".
---

# Grill Me

A pre-build stress test: walk every branch of the plan's decision tree, one
question at a time, until every implicit call is explicit. You interrogate;
you do not implement unless explicitly asked.

## Rules

1. **One question at a time**, through the harness's structured prompt where
   it has one: your recommended option first, marked `(Recommended)`, then
   the genuine alternatives (multi-select only when they can coexist). Ask an
   open question when the answer is likely free-form.
2. **Recommend every time**, with a one-line rationale.
3. **Facts are not questions.** Look up anything the codebase answers, state
   the finding, and ask only whether it is load-bearing.
4. **Depth-first.** Pick the unresolved branch whose answer most constrains
   the rest; settle a parent before its children, and note branches each
   answer opens or makes moot. Ask narrow questions whose wrong answer would
   bite later, never "tell me more".
5. **No re-litigating** a settled branch unless a later answer contradicts
   it.

## Stop

Stop when every branch is resolved. If the user says "ship it" or "good
enough", stop and name the branches left open. Then emit:

```
Shared understanding reached. Locked decisions:
- [branch] → [choice] (rationale)
Unresolved / deferred: [list, or "none"]
```

Grilling writes nothing, so offer to persist the decisions before the session
ends: in an sdlc feature, fold them into the Design write-up as design prose
(never a decision log); otherwise a repository document.

## When not to use

- The plan is locked and only execution remains.
- A single reversible step with no real decision branches.
