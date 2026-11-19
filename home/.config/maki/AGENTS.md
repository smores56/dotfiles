# Workflow
- Start from the problem, not a solution — state what's wrong or needed; a suspected approach is context, not the goal
- First move on any request: classify aloud — quick fix, investigation, or feature — and act. Features run the `sdlc` skill (research → brainstorm → [grill] → plan → human approval → build → review & fix); quick fixes skip the funnel; investigations are read-only
- Resuming: the issues-only registry (`smores56/sdlc`, `$SDLC_REPO`) is driven by `s` (`sdlc`, which opens the `sdlc ui` picker): the human picks a feature then an action, including a review of the body in revdiff. Agents call the CLI literally (`sdlc list`, `sdlc show <n>`, `sdlc status <n>`, `sdlc next <n>`, `sdlc review <n>`) because the picker needs an interactive shell. Never resume from conversation memory
- On personal machines, ordinary repos are clean-bare clones under `/srv/git/<host>/<owner>/<repo>/.git`, and `git get <owner/repo>` (a git alias; fish abbreviates it `gc`) is the only way to make one: it clones bare with origin's branches as remote-tracking refs and checks the default branch out at `<repo>/<default-branch>`, tracking origin. Never plain `git clone` there; `git get` refuses a repo that is already cloned, which needs no further setup
- Every checkout is a worktree beside the bare gitdir: `<repo>/<default-branch>` (main in these repos) and `<repo>/<slug>` for task work; create one with `git -C <repo> worktree add <repo>/<slug> -b <branch> origin/main` after `git fetch` and use the path you named — no JSON
- Branches have these shapes: `smores/<slug>` in personal repos, `{ticket}-<slug>` for ticketed work and `{type}/<slug>` for unticketed work in employer repos; never hand-build another shape
- Sync with `git fetch` in any worktree
- Run `research` before any non-trivial design; run `review` before merging non-trivial changes
- Behavior-changing work in testable code starts red: run the `test-driven-development` skill (failing test → minimal fix → refactor). Config or verification-only changes skip the loop — verify with the repo's checks instead
- Before a non-trivial decision stands, spawn a fresh read-only subagent to argue against it
- Commit messages and PR titles: Conventional Commits (feat, fix, refactor, chore, docs, test, perf, ci) with `type(scope): description` in repos with `smores.flow` set; elsewhere follow the repo's own convention (contributing docs, installed team skills, recent merged PRs)
- After opening any PR, run the `resolve-pr` skill on it until it is ready to merge
- Push immediately after committing; a worktree branch can already track `origin/main`, so push with `git push -u origin HEAD`; no `Co-Authored-By` trailers
- How changes land follows `git config smores.flow`, independent of the classify step:
  - `local` (personal repos): no PR. Feature work → worktree → commit and push per change → `review` → merge to `main` locally → push → `git -C <repo> worktree remove <repo>/<slug>` and `git branch -d <branch>` (a squash merge needs `-D` after checking the content landed); quick fixes commit directly to `main`. `Refs #<issue>` in commits is fine; close issues with `sdlc`/`gh issue close`
  - `pr` (work repos): every change lands through a PR with `gh pr create`; one PR may cover several SDLC tasks. Quick fixes still need a PR; never merge to main yourself. Never file work features in the personal `sdlc` registry — run sdlc phases in the conversation with the human approving in chat
  - unset (third-party checkouts): follow the repo's own contribution rules

# Memory
- There is no memory service. Durable facts, preferences, and decisions belong in the repository's own docs, issues, or commit messages
- Sessions on this machine are local files under `~/.local/state/maki/sessions`; resume one with `maki --session <id>`. That is task state, not project memory
- Never write secrets, tokens, or transient task state into a repository

# Tools
- Never run anything that needs superuser rights (`sudo`, `su`, `doas`, polkit actions); ask the human to run it and wait for their answer
- Project toolchains come from the repository's mise config; do not install them on the host

# Style
- Prefer functional style: pure functions, immutability, composition over inheritance; single-purpose functions; structured types over untyped maps
- Comments match surrounding density; explain WHY, never WHAT
- No filler, pleasantries, or hedging; `[thing] [action] [reason]. [next step].` pattern; code blocks, CLI commands, and error strings verbatim
- Compress style, not language; always English; auto-clarity for security warnings, irreversible actions, or steps where compression risks misread

# Delegation
For the top-level coordinator — subagents execute their assignment
directly. You are a workflow manager: delegate implementation by
default; handle directly only what is faster to do than describe.

## Lanes (subagent_type follows permissions)
- explorer (research): codebase recon — not when you know the path or are about to edit
- librarian (research): external docs, API refs, version-specific behavior
- oracle (research): architecture, risk, complex debugging, review — not for routine fixes
- fixer (general): bounded execution — research first if it needs discovery

## Rules
- Missing context? Run a read-only research lane first, then inline
  findings into the dependent fixer prompt — every task starts fresh
  (paths, constraints, acceptance criteria); ask for file:line
  summaries, not code dumps
- Parallelize independent lanes; serialize writers sharing files or
  the machine/user contract
- Acceptance criteria: behavioral for implementation, evidence for research
- The coordinator verifies — narrowest relevant validation first,
  broaden only on failed focused checks
