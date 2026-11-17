---
name: design-brainstorm
description: Explore a wide set of options, then compare them honestly — at least three architecturally distinct alternatives, each with a reason, before converging on one.
---

# Design Brainstorm

A thinking partner during design, not implementation. The user wants a wide,
well-reasoned set of options and an honest comparison, not the first
reasonable idea. Resist converging early.

## Phase 0 — Consume the research brief

No brief for this problem means run `research` first. Designs grounded in an
imagined landscape waste the divergence below.

## Phase 1 — Diverge

Restate the request as one crisp **"How Might We ..."** statement. If you
cannot state it compactly, it is a vibe, not a design.

Ask at most five sharpening questions, one at a time: who it is for, what
success looks like, the real constraints, what was tried, why now. Read the
codebase for facts instead of asking. Do not proceed until the target is
clear.

Then produce alternatives. **Minimum three architecturally distinct
approaches**; six when the space is genuinely open. Distinct means they differ
in a core decision — data model, control flow, where state lives, sync vs
async, build vs buy, who operates it — not three variants of one idea. Useful
lenses: inversion, constraint removal, audience shift, 10x simplification, 10x
scale, what a domain expert would find obvious.

For each: a one-line name, the core idea, the mechanism that makes it work,
and what it costs (effort, risk, operational load, new dependency).

## Phase 2 — Compare

One table, no prose blob. Minimum three rows; every row carries a reason.

| Option | Core mechanism | Fit | Cost | Why not |
|---|---|---|---|---|
| A | ... | ... | ... | chosen / rejected because ... |

Rules for the table:

- Judge each option against the framed questions, not against your favorite.
- Cite evidence from the brief (`file:line`, URL); an option resting on an
  unverified assumption says so.
- Name the deal-breaker for every rejected option. "Less clean" is not a
  reason; "needs a second credential" is.
- State the recommendation and the one residual risk you accept with it.

## Phase 3 — Converge

Recommend one direction and the two decisions it hinges on. Then stop: the
user picks, or `grill-me` walks the remaining branches. Do not write the
implementation plan here.

For an SDLC feature, fold the surviving table into the design's "Alternatives
considered" section — option, why not, evidence — and keep the reasoning, not
the conversation. Never mark a design approved from this skill; approval is
the user's step.

## Red flags

- One option dressed as three
- Converging before the landscape is mapped
- A comparison with no rejected row, or with a cost column of adjectives
- Silently designing around a constraint nobody stated
- Treating the recommendation as a decision
