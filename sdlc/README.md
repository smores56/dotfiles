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
sdlc list [--all] [--repo OWNER/REPO] [--format human|path|json]
sdlc show FEATURE                   # body + comment thread
sdlc status FEATURE                 # design hash, approval, task counts
sdlc next [FEATURE]                 # next ready task, or the blocker
sdlc approve FEATURE [--yes]        # human gate: label + hash comment
sdlc new SLUG --repo OWNER/REPO     # create the feature issue
sdlc task add FEATURE TITLE [--needs T1,T2|10,12]
sdlc task edit ISSUE [--needs T1,T2|10,12] [--title TITLE]
sdlc task start|done|cancel ISSUE
sdlc complete|cancel FEATURE
sdlc pick [--all] [--repo OWNER/REPO]   # fzf: pick a feature, then an action
sdlc review FEATURE [--dry-run]     # revdiff review -> issue comment
sdlc comment FEATURE                # comment in $EDITOR
```

`sdlc pick` shells out to `fzf`: one list of features with `sdlc show` as the
preview, then the action list. It needs a terminal, so agents never call it.

## Interactive dashboard (`gh sdlc`)

`gh sdlc` opens [gh-dash] on the registry. It is a local gh extension
(`home/.local/bin/gh-sdlc`, also linked into gh's extension directory) plus a
dedicated config (`home/.config/sdlc/gh-dash.yml`). It does not change this
CLI; agents keep using the non-interactive commands.

Build the smores56 gh-dash fork once, then apply the dotfiles:

```sh
git get smores56/gh-dash
cd /srv/git/github.com/smores56/gh-dash/main
MISE_LOCKED=0 mise x go@1.27.1 -- go build \
  -ldflags '-X github.com/dlvhdr/gh-dash/v4/cmd.Version=v4.26.3-sdlc' -o gh-dash .
mkdir -p ~/.local/share/gh/extensions/gh-dash
cp gh-dash ~/.local/share/gh/extensions/gh-dash/gh-dash
mise dot apply
gh sdlc
```

The fork keeps v4.26.3 but uses an issue-only repository type, so the issue
query no longer asks for `repository.branchProtectionRules` — a field private
repos on the Free plan cannot read (upstream
[#562](https://github.com/dlvhdr/gh-dash/issues/562)). The wrapper requires the
`v4.26.3-sdlc` version marker. `?` lists all nine named verbs.

Sections are Features, In progress, Unapproved, Re-approval, Tasks, and Closed.
`Unapproved` is the absence of the approval label; `Re-approval` is the explicit
`status:needs-reapproval` label. `/` filters the current section; `r` refreshes
it and `R` refreshes every section.

Keys on a selected issue:

| Key | Action |
| --- | --- |
| `S` | `sdlc status` (design hash, approval, task counts) |
| `N` | `sdlc next` (next ready task) |
| `v` | `sdlc review` (revdiff → comment) |
| `V` | `sdlc approve` (prompts) |
| `D` | `sdlc complete` (confirms; refuses open tasks) |
| `x` | `sdlc cancel` (confirms) |
| `T` | `sdlc task start` |
| `d` | `sdlc task done` (confirms) |
| `ctrl+x` | `sdlc task cancel` (confirms) |

The wrapper pins `SDLC_REPO=smores56/sdlc` and `SDLC_TRANSPORT=gh`; a second
registry needs its own config and wrapper. Every key passes the row's repo, so a
row from another repo is refused. `--config` makes gh-dash read only this file;
the global gh-dash config does not apply. The custom `x` replaces gh-dash's
close; `t` remains smart filtering. `s` cycles gh-dash's views; only the
Issues view has the sdlc verbs, and the PR view is intentionally empty. The
Closed section is browse-only: the verbs refuse closed issues. Press `R` to
refresh every section after an action.

[gh-dash]: https://github.com/dlvhdr/gh-dash

## Transports

`SDLC_TRANSPORT` picks the backend:

- `gh` (default): shells out to `gh`, which owns the credential.
- `broker`: plain HTTP to `${BROKER_URL}/github-sdlc/<api.github.com path>`, a
  proxy that injects the GitHub App bearer. The client never sends an
  `Authorization` header.

REST issue reads carry no comments, sub-issues or blockers, so the broker
transport fetches those from their own endpoints, and sub-issue and dependency
writes resolve issue numbers to database ids first. `status`, `next` and
`complete` use one GraphQL call because `blockedBy` has no bulk REST read.

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
