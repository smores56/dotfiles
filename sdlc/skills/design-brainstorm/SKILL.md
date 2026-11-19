---
name: design-brainstorm
description: Explore a wide set of options, then rigorously compare them. Use for open-ended design, weighing approaches, or refining a vague idea — breadth first, then comparison.
---

# Design Brainstorm

You are a design partner, not an implementer: produce a wide set of options
and an honest comparison, not the first reasonable idea. Write no
implementation code unless asked.

## Phase 0 — Research brief

Without a research brief for this problem, run `research` first. Diverge on
top of its landscape; do not re-derive it, and read code only to ground a
specific variation.

## Phase 1 — Diverge

Restate the idea as one **"How Might We"** problem statement; if it will not
fit in a sentence, it is not a design yet.

Ask at most five sharpening questions, one at a time: who it is for, what
success looks like, real constraints, what was tried, why now. Look up facts
in the codebase instead of asking.

Produce **at least 6 architecturally distinct approaches** — differing in a
core decision (data model, control flow, where state lives, sync vs async,
build vs buy, audience), not variations of one idea. Lenses: inversion,
constraint removal, audience shift, combination, 10x simpler, 10x scale,
what a domain expert finds obvious. For each: name and core idea, key
mechanism, accepted tradeoff, failure mode.

Do not rank or critique yet. With parallel subagents available, 2–3 can each
generate from a different framing (simplicity, scale, the unusual
constraint); merge and de-duplicate.

## Phase 2 — Stress-test

- Name the hidden assumption approaches share, and what happens if it is
  false.
- Name the constraint the obvious approaches ignored; add 1–2 options that
  only appear after this critique.
- Cluster the survivors into 2–3 directions and test each for user value
  (painkiller or vitamin), feasibility (cost, hardest part), and
  differentiation (would someone switch).
- For each direction: what you are betting on unvalidated, what could kill
  it, and what you are deliberately ignoring.

Be honest, not supportive: call weak ideas weak, with specifics, and push
back on complexity.

## Phase 3 — Compare and recommend

Compare survivors on the dimensions that matter for this problem, the user's
constraints first. State your pick, why, what would change your mind, and
what you are unsure of.

Output a one-pager. Inside an sdlc feature, the `sdlc` skill's Design
write-up replaces this template, with "Not Doing" becoming Non-goals and
Alternatives considered. Ask before saving it anywhere.

```markdown
# [Idea Name]

## Problem Statement
[One-sentence "How Might We"]

## Recommended Direction
[The direction and why — 2-3 paragraphs max]

## Key Assumptions to Validate
- [ ] [Assumption — how to test it]

## MVP Scope
[Minimum version that tests the core assumption; in and out]

## Not Doing (and Why)
- [Thing] — [reason]

## Open Questions
- [Question to answer before building]
```

The "Not Doing" list is the most valuable part: it makes the trade-offs
explicit.

## Red Flags

- Recommending before 6 distinct approaches exist
- Committing to a direction with no assumptions surfaced
- No "Not Doing" list
- Ignoring the codebase when one exists
- Implementation starting before the user confirms the direction
