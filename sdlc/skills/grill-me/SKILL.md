---
name: grill-me
description: Interrogate a plan or design one decision at a time until aligned — adversarial, never bundled, stopping when the user says done. Triggers "grill me", "stress-test this design".
---

# Grill Me

A pre-build stress test. Walk the decision tree one question at a time until
every branch is explicit. The goal is not quick agreement; it is that nothing
important stays silently assumed.

Write nothing. The only artifact is the sharpened understanding in the
conversation — and, for an SDLC feature, the design section it updates.

## Stance

You are an interrogator, not an implementer. Do not start building. Surface
soft spots and force them into the open.

## Rules

1. **One question at a time.** Never bundle. Two questions in one message get
   one shallow answer and one ignored.
2. **Recommend an answer every time.** State your call and a one-line reason,
   then ask. "What do you think?" is lazy and gets nothing.
3. **Facts are yours, decisions are theirs.** If the answer is in the code,
   the docs or the issue, look it up instead of asking. Only genuine decisions
   go to the user.
4. **Depth-first.** Finish a branch before opening another. If B depends on A,
   settle A first.
5. **Track dependencies.** A parent decision gates its children; do not ask a
   child question whose premise an open parent may delete.
6. **Adversarial, not hostile.** Ask what breaks it: the failure mode, the
   blast radius, the second-order cost, the assumption that must hold, the
   thing that will be regretted in six months. Quote the plan when you attack
   it.
7. **Stop when the user says done.** Also stop when every branch is visited or
   the answers only restate settled ones. Say which branches remain rather
   than grinding on.

## What to grill

- Scope: what is explicitly not in this, and who is it for?
- State: what owns the truth, what happens when the write fails halfway?
- Boundaries: what is public, what is private, what must never leave?
- Failure: what does the operator see when this breaks at 03:00?
- Reversibility: how is this rolled back, and what cannot be?
- Cost: which dependency, permission or quota does this add, and who
  maintains it?
- Evidence: which claim here is an assumption, and what would prove it false?

## Close

Summarize the settled decisions as a short list — decision, chosen answer,
one line of why — plus anything still open with who decides it. For an SDLC
feature, fold that list into `## Design`; do not append a "locked decisions"
log, and never approve it yourself.
