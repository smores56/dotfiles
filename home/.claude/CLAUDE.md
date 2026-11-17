# Workflow
- Start from the problem, not a solution — state what's wrong or needed; a suspected approach is context, not the goal
- First move on any request: classify aloud — quick fix, investigation, or feature — and act. Features run the `sdlc` skill (research → brainstorm → [grill] → plan → human approval → build → review & fix); quick fixes skip the funnel; investigations are read-only. In `pr`-flow work repos the skill's phases run in the conversation, without the personal registry
- Resuming (personal machines): the issues-only registry (`smores56/sdlc`, `$SDLC_REPO`) is driven by `s`: the human picks a feature then an action (`sr` reviews the body in revdiff and posts the notes); agents call the CLI literally (`sdlc list`, `sdlc show <n>`, `sdlc status <n>`, `sdlc next <n>`), because the `sl`/`ss`/`st`/`sn` abbreviations exist only in an interactive shell. Never resume from conversation memory
- Ordinary repos live under `/srv/git/github.com/<owner>/<repo>`; clone with `repos get <owner/repo>` — never `git clone`, `git worktree add`, `git checkout -b`, or Claude's EnterWorktree
- Worktrees live under each repo's `.worktrees/` via `worktrees new`; it prints JSON — use its `path` as cwd, never `cd`
- Start task worktrees with `worktrees new --slug <kebab-slug> --task "<description>"` (creates branch + worktree); pass `--ticket <KEY>` whenever the work has a ticket (repos that don't name branches by ticket ignore it) and `--type <fix|feat|…>` when it asks for one
- Branches come from `worktrees new`, which renders the repo's template (`git config smores.branchTemplate`); never hand-build a branch name, even where an installed team skill shows `git checkout -b`
- Run `research` before any non-trivial design; run `review` before merging non-trivial changes
- Behavior-changing work in testable code starts red: run the `test-driven-development` skill (failing test → minimal fix → refactor). Config or verification-only changes skip the loop — verify with the repo's checks instead
- Before a non-trivial decision stands, spawn a fresh read-only subagent to argue against it
- Commit messages and PR titles: Conventional Commits (feat, fix, refactor, chore, docs, test, perf, ci) with `type(scope): description` in repos with `smores.flow` set; elsewhere follow the repo's own convention (contributing docs, installed team skills, recent merged PRs)
- Push immediately after committing; no `Co-Authored-By` trailers
- How changes land follows `git config smores.flow`, independently of the classify step (quick fix | investigation | feature) that decides whether the SDLC funnel runs:
  - `local` (personal repos): no PR. Feature work → worktree → commit and push per change → `review` → merge to `main` locally → push → `worktrees prune --apply`; quick fixes commit directly to `main`; investigations are read-only. `Refs #<issue>` in commits is fine; close issues with `sdlc`/`gh issue close`
  - `pr` (work repos): every change lands through a PR with `gh pr create`; one PR may cover several SDLC tasks. Quick fixes may skip the SDLC funnel but still need a PR; never merge to main yourself. Never file work features in the personal `sdlc` registry — run sdlc phases in the conversation with the human approving in chat
  - unset (third-party checkouts): follow the repo's own contribution rules

# Memory
- Claude Code's memory files are the agent memory: keep durable facts, preferences, and decisions the repo and its docs don't hold, one self-contained fact per entry
- Check memory before work that earlier sessions may have touched
- Never write secrets, tokens, or transient task state

# Tools
- Never run anything that needs superuser rights (`sudo`, `su`, `doas`, polkit actions); ask the human to run it and wait for their answer

# Style
- Prefer functional style: pure functions, immutability, composition over inheritance; single-purpose functions; structured types over untyped maps
- Comments match surrounding density; explain WHY, never WHAT
- No filler, pleasantries, or hedging; `[thing] [action] [reason]. [next step].` pattern; code blocks, CLI commands, and error strings verbatim
- Compress style, not language; always English; auto-clarity for security warnings, irreversible actions, or steps where compression risks misread

# Machine
@~/.claude/work.md
