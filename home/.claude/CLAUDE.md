# Workflow
- Start from the problem, not a solution — state what's wrong or needed; a suspected approach is context, not the goal
- First move on any request: classify aloud — quick fix, investigation, or feature — and act. Features run the `sdlc` skill (research → brainstorm → [grill] → plan → human approval → build → review & fix); quick fixes skip the funnel; investigations are read-only. In `pr`-flow work repos the skill's phases run in the conversation, without the personal registry
- Resuming (personal machines): the issues-only registry (`smores56/sdlc`, `$SDLC_REPO`) is driven by `s` (`sdlc ui`): the human picks a feature then an action, including a review of the body in revdiff. Agents call the CLI literally (`sdlc list`, `sdlc show <n>`, `sdlc status <n>`, `sdlc next <n>`, `sdlc review <n>`) because the picker needs an interactive shell. Never resume from conversation memory
- On a ghq machine, ordinary repos are clean-bare clones under `/srv/git/<host>/<owner>/<repo>/.git`: clone with `ghq get --clean-bare <owner/repo>`, then run the checkout recipe — never plain `git clone` there, never `ghq get -u`:
  ```
  ghq get --clean-bare <owner/repo>
  repo="$(ghq root)/github.com/<owner>/<repo>"
  git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$repo" worktree add "$repo/main" main
  git -C "$repo/main" fetch origin
  git -C "$repo/main" branch --set-upstream-to=origin/main
  ```
- Every checkout is a worktree beside the bare gitdir: `<repo>/main` for the default branch and `<repo>/<slug>` for task work; create one with `git -C <repo> worktree add <repo>/<slug> -b <branch> origin/main` after `git fetch` and use the path you named — no JSON
- Branches have these shapes: `smores/<slug>` in personal repos, `{ticket}-<slug>` for ticketed work and `{type}/<slug>` for unticketed work in employer repos; never hand-build another shape
- Sync with `git fetch` in any worktree; `ghq get -u` refuses to update a branch that is checked out, so it is never used
- Run `research` before any non-trivial design; run `review` before merging non-trivial changes
- Behavior-changing work in testable code starts red: run the `test-driven-development` skill (failing test → minimal fix → refactor). Config or verification-only changes skip the loop — verify with the repo's checks instead
- Before a non-trivial decision stands, spawn a fresh read-only subagent to argue against it
- Commit messages and PR titles: Conventional Commits (feat, fix, refactor, chore, docs, test, perf, ci) with `type(scope): description` in repos with `smores.flow` set; elsewhere follow the repo's own convention (contributing docs, installed team skills, recent merged PRs)
- Push immediately after committing; a worktree branch can already track `origin/main`, so push with `git push -u origin HEAD`; no `Co-Authored-By` trailers
- How changes land follows `git config smores.flow`, independently of the classify step (quick fix | investigation | feature) that decides whether the SDLC funnel runs:
  - `local` (personal repos): no PR. Feature work → worktree → commit and push per change → `review` → merge to `main` locally → push → `git -C <repo> worktree remove <repo>/<slug>` and `git branch -d <branch>` (a squash merge needs `-D` after checking the content landed); quick fixes commit directly to `main`; investigations are read-only. `Refs #<issue>` in commits is fine; close issues with `sdlc`/`gh issue close`
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
