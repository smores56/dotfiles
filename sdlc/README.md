# sdlc

The sdlc CLI and the phase skills every agent loads. The registry
(`$SDLC_REPO`, default `smores56/sdlc`) holds one issue per feature: Design and
Plan in the body, tasks as sub-issues, approval as a label plus a design-hash
comment. The CLI keeps no local state.

`sdlc_issues.py` is stdlib-only Python 3.11+. The dotfiles base environment
links it to `~/.local/bin/sdlc`; re-apply the dotfiles after changing it.
Elsewhere, `uv tool install .` (or `pipx install .`) builds the same console
script from `pyproject.toml`.

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
sdlc ui [ACTION] [FEATURE]          # picker (the default); uses tv when present
sdlc review FEATURE [--dry-run]     # revdiff review -> issue comment
sdlc comment [FEATURE]              # comment in $EDITOR
sdlc hook add OWNER/REPO --url URL [--events a,b] [--secret-file PATH]
```

## Transports

`SDLC_TRANSPORT` picks the backend:

- `gh` (default): shells out to `gh`, which owns the credential.
- `broker`: plain HTTP to `${BROKER_URL}/github-sdlc/<api.github.com path>`, a
  proxy that injects the GitHub App bearer. The client never sends an
  `Authorization` header.

REST issue reads carry no comments, sub-issues or blockers, so the broker
transport fetches those from their own endpoints, and sub-issue and dependency
writes resolve issue numbers to database ids first. `status`, `next`,
`complete` and `ui` use one GraphQL call because `blockedBy` has no bulk REST
read.

`sdlc hook add` posts through a second broker host, `${BROKER_URL}/github-hooks`,
which proxies `POST /repos/OWNER/REPO/hooks` and nothing else, so there is no
list or delete. `--url` must sit under `https://agent-hooks.sammohr.dev/`;
`--secret-file` is sent as `config.secret` and never printed.

## Agents

Agents hold no GitHub credential: they clone through the broker's git proxy
and run the CLI from the checkout.

```sh
git clone "$BROKER_URL/github-sdlc-git/smores56/dotfiles.git"
SDLC_TRANSPORT=broker ./dotfiles/sdlc/sdlc_issues.py list
```

The broker enforces no approval predicate, so the rule lives with the human
and the `sdlc` skill: agents never run `sdlc approve` (or pass `--yes`) unless
the user explicitly says to approve.

## Tests

```sh
python3 -m unittest discover -s tests
```
