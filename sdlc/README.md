# sdlc

Source for the sdlc CLI and its phase skills, vendored into the dotfiles
repository. The registry (`smores56/sdlc`) is now issue state only: one issue
per feature, Design + Plan in the body, tasks as sub-issues, approval as a
label plus a design-hash comment.

`sdlc_issues.py` is a stdlib-only Python package (3.11+) that talks to GitHub
through a pluggable transport: `gh` by default, or plain HTTP through the
broker. It keeps no local state.

## Use from dotfiles

The dotfiles identity environment links `sdlc_issues.py` to
`~/.local/bin/sdlc`; there is no install step and no private clone. Re-apply
the dotfiles after changing the source.

Standalone, from this directory:

```sh
uv tool install .     # -> ~/.local/bin/sdlc
pipx install .        # same console script, pipx-managed venv
pip install .         # into the active environment (or --user)
sdlc list
```

All three build the same wheel from `pyproject.toml`; there is no separate
install path and no runtime dependency beyond Python (plus `gh` on `PATH` when
`SDLC_TRANSPORT` is unset).

## Transports

`SDLC_TRANSPORT` picks the backend. Anything other than `gh` or `broker` fails
with a clear error.

- `gh` (default, unset): shells out to `gh`, which owns the credential. Human
  hosts use this.
- `broker`: every GitHub call is an HTTP request to
  `${BROKER_URL}/github-sdlc/...`, a path proxy that injects the GitHub App
  bearer. The client sends no token and never adds an `Authorization` header.

```sh
SDLC_TRANSPORT=broker BROKER_URL=http://broker:8080 sdlc list
```

The broker path maps 1:1 onto `api.github.com`
(`/github-sdlc/repos/OWNER/REPO/issues`), and the CLI parses the same payload
shapes either way. Two places REST differs from `gh` and the client composes
calls instead: the issue list/view endpoints carry no comments, sub-issues or
blocked-by links, so those come from `.../comments`, `.../sub_issues` and
`.../dependencies/blocked_by`; and sub-issue/dependency writes take integer
database ids, so creating a task first resolves the parent's and blockers' ids.
`status`, `next`, `complete` and `ui` still use one GraphQL round trip
(`POST /github-sdlc/graphql`) because `blockedBy` has no bulk REST read.

## Repo hooks

`sdlc hook add` registers a GitHub repository webhook through a broker logical
host of its own, `${BROKER_URL}/github-hooks`:

```sh
sdlc hook add smores56/sdlc \
  --url https://agent-hooks.sammohr.dev/hook/<capability>
```

The broker injects an installation token with `repository_hooks: write` and
proxies `POST /repos/OWNER/REPO/hooks` alone. That is also the whole CLI
surface: `list` and `delete` do not exist because the broker refuses `GET`,
`PATCH` and `DELETE` on that path. `--url` must sit under
`https://agent-hooks.sammohr.dev/`; the CLI rejects anything else before
sending, rather than letting the broker answer 403. Default events are `push`,
`pull_request`, `issues` and `issue_comment` (`--events` takes a comma list).
`--secret-file` reads the webhook secret, sends it in `config.secret`, and
never prints it. On the `gh` transport the same call is:

```sh
gh api repos/OWNER/REPO/hooks -X POST --input -   # JSON body on stdin
```

## Agent bootstrap

Agents have no GitHub credential of their own; they clone this repository
through the broker's git proxy and run the stdlib CLI from the checkout:

```sh
git clone "$BROKER_URL/github-sdlc-git/smores56/dotfiles.git"
export SDLC_TRANSPORT=broker BROKER_URL=http://broker:8080   # in the agent env
./dotfiles/sdlc/sdlc_issues.py list
```

The nanobot entrypoint previously copied `skills/` from the `smores56/sdlc`
registry; that repository is issue state only, so its clone must point at this
checkout instead.

Approval stays procedural: agents must not run `sdlc approve` (or pass `--yes`)
unless the user explicitly says to approve. The broker grants the App write
access and enforces no approval predicate, so the rule lives with the human and
the `sdlc` skill, not the server.

## Layout

- `sdlc_issues.py` — the CLI
- `skills/` — nanobot agent skills, overlaid at pod start (`skills/README.md`)
- `tests/` — stdlib unittest suite (`python -m unittest discover -s tests -v`)

## Commands

```text
sdlc list [--all] [--repo OWNER/REPO] [--format human|path|json] [--pick]
sdlc show FEATURE                   # body + comment thread
sdlc status FEATURE                 # design hash, approval, task counts
sdlc next [FEATURE] [--pick]        # next ready task, or the blocker
sdlc approve FEATURE [--yes]        # human gate: label + hash comment
sdlc new SLUG --repo OWNER/REPO     # create the feature issue
sdlc task add FEATURE TITLE [--needs T1,T2|10,12]
sdlc task start|done|cancel ISSUE
sdlc complete|cancel FEATURE
sdlc ui [ACTION] [FEATURE]          # picker; uses tv when present
sdlc review FEATURE [--dry-run]     # revdiff review -> issue comment
sdlc comment [FEATURE]              # comment in $EDITOR
sdlc hook add OWNER/REPO --url URL [--events a,b] [--secret-file PATH]
```

The registry repo defaults to `$SDLC_REPO`, then `smores56/sdlc`.
