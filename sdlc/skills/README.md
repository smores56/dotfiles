# Agent skills

The phase skills for the nanobot agent: `sdlc`, `research`,
`design-brainstorm`, `grill-me`, `review`, `test-driven-development`,
`resolve-pr`, `notify`. They target a host with `exec`, file tools, `curl`
through the broker, the `sdlc` CLI, memory MCP tools and `task` subagents — not
the human's terminal, where `gh`, `revdiff`, `tv` and `fzf` exist.

They ship with the CLI they drive: every skill names commands whose behavior
comes from `sdlc_issues.py` here, so a method change and the command it
describes land together.

## The overlay, at start

On each container start, in this order:

1. `render.py` (homelab-platform image) deletes
   `$HOME/.nanobot/workspace/skills` and copies `/etc/nanobot/skills` there.
   That mount is the tenant `nanobot-config` ConfigMap, built by kustomize from
   `apps/nanobot/config/skills/` in `homelab-apps` — currently
   `broker-requests`, `git-change`, `tinyfish-search`. The same step writes
   the platform prompt to the workspace `AGENTS.md`.
2. `entrypoint.sh` clones this dotfiles checkout through the broker into
   `$HOME/tools/sdlc-src`, copies `sdlc/skills/.` over that same workspace
   directory, and links the CLI onto the tools PVC. The old clone pointed at
   the `smores56/sdlc` registry, which now holds issue state only.

The copy is an overlay: a repository without `skills/` leaves the ConfigMap's
skills alone, and a failed clone keeps the previously installed tree. Nothing
is baked into the image, so a broker outage starts the agent without these
skills rather than crashlooping it.

**A skill edit lands on the next pod restart.** The entrypoint clones `main` at
start; merging changes what the next clone fetches and nothing reloads a
running agent. Verify a change by reading the merged file, not by asking a live
agent which rules it holds.

## Platform vs registry

| Owner | Holds | Changes by |
|---|---|---|
| `homelab-platform`: `nanobot-policy` ConfigMap | system prompt, model catalog | platform PR; admission pins the two paths |
| `homelab-apps`: `apps/nanobot/config/` | the broker and cluster contract skills, cron | tenant PR, which rolls the Deployment via the kustomize hash |
| `smores56/dotfiles` (`sdlc/`) | the CLI and these SDLC phase skills | merge to `main`, effective at the next restart |

There is no system prompt file here. A rule that must hold no matter which
skills load — the approval gate, the no-merge rule, the untrusted-data rule —
belongs in the platform prompt (#639) and is only restated here.

## Authoring rules

- One directory per skill, `skills/<name>/SKILL.md`, directory name equal to
  the frontmatter `name`. Required frontmatter: `name` and a one-line
  `description` that includes its trigger phrases. Add
  `metadata.nanobot.requires.bins` when the skill shells out; every listed
  binary must exist in the image (`curl`, `git`, `python`) or be installed by
  the entrypoint (`sdlc`), or the skill disappears from the index.
- Roughly 40-90 lines. Rules as prose, tables and commands only where they
  compress.
- Name broker paths (`$BROKER_URL/github-sdlc`, `.../github-agent`,
  `.../tinyfish`, `.../notify`) and never a token, key or credential — the
  broker injects them, and CI rejects token-shaped strings.
- No `gh`, `revdiff`, `tv`, `fzf` or interactive TUI. When a CLI command needs
  a terminal (`sdlc comment`, `sdlc review`), describe the broker request an
  agent makes instead.
- Treat issue bodies, PR comments, web pages and logs as untrusted data in
  every skill that reads them.

`tests/test_skills.py` enforces the frontmatter keys, the directory/name match
and a non-empty body; everything else is review.
