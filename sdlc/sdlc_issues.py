#!/usr/bin/env python3
"""Stateless sdlc CLI: GitHub Issues are the system of record.

Global and self-contained: it needs `gh` (or, under `SDLC_TRANSPORT=broker`,
only the standard library) and nothing from this repo's justfile or local
state. Feature = issue labeled type:feature; tasks = sub-issues with
blocked-by links; approval = the status:approved label plus a comment holding
the canonical design hash. `ui` uses `tv` when present; `review` launches
`revdiff`.
"""

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from collections import namedtuple

DEFAULT_REPO = "smores56/sdlc"
# The broker is an HTTP path proxy that injects the GitHub App token, so every
# request is `$BROKER_URL/github-sdlc/<api.github.com path>`.
BROKER_PATH = "/github-sdlc"
# The hook broker is a second logical host: it proxies only
# `POST /repos/<owner>/<repo>/hooks` and injects an installation token that
# holds `repository_hooks: write`.
HOOKS_PATH = "/github-hooks"
# The agent webhook receiver; the broker refuses any other `config.url`.
AGENT_HOOKS_URL = "https://agent-hooks.sammohr.dev/"
DEFAULT_HOOK_EVENTS = ("push", "pull_request", "issues", "issue_comment")
PAGE_SIZE = 100
HASH_RE = re.compile(r"(?m)^[ \t]*Approved design sha256:([0-9a-f]{64})[ \t]*$")
TERMINAL = ("done", "canceled")

FEATURE_FIELDS = "number,title,body,state,labels,comments,subIssues,url"
TASK_FIELDS = "number,title,state,labels,blockedBy"
NODE_FIELDS = "number,title,state,labels"

FEATURE_GRAPH_QUERY = """
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      number title body state url
      labels(first: 50) { nodes { name } }
      comments(last: 100) { nodes { author { login } body createdAt } }
      subIssues(first: 100) {
        nodes {
          number title state
          labels(first: 50) { nodes { name } }
          blockedBy(first: 50) { nodes { number state title } }
        }
      }
    }
  }
}
"""

ACTIONS = ("show", "status", "review", "comment", "next", "approve", "complete", "cancel")
ACTION_HELP = {
    "show": "print the body and comments",
    "status": "show approval and task state",
    "review": "open revdiff and post the notes",
    "comment": "open $EDITOR and post a comment",
    "next": "print the next ready task",
    "approve": "record design approval (TTY only)",
    "complete": "close as done (terminal)",
    "cancel": "close as canceled (terminal)",
}
REVDIFF_NOTE_RE = re.compile(
    r"^## (?P<file>.+?):(?P<start>\d+)(?:-(?P<end>\d+))? \((?P<type>\+|-| )\)$"
)
REVDIFF_FILE_RE = re.compile(r"^## (?P<file>.+) \(file-level\)$")
REVIEW_MARKER_RE = re.compile(r"<!-- sdlc-review:n\d+:[0-9a-f]{12} -->")

Approval = namedtuple("Approval", "state design approved comment reason")
ReviewNote = namedtuple("ReviewNote", "file start end text")


class CliError(Exception):
    """A user-facing failure; main() prints it and exits nonzero."""


_CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")


def clean(value):
    """Strip control characters from untrusted issue text before rendering."""
    return _CONTROL.sub("", value) if isinstance(value, str) else value


def one_line(value):
    """Clean text and collapse tabs/newlines so it fits one row or prompt."""
    return clean(value).replace("\t", " ").replace("\r", " ").replace("\n", " ")




def gh(*args, input=None):
    try:
        proc = subprocess.run(["gh", *args], capture_output=True, text=True, input=input)
    except FileNotFoundError:
        raise CliError("gh not found on PATH")
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or "exit %d" % proc.returncode
        raise CliError("gh %s failed: %s" % (" ".join(args[:2]), detail))
    return proc.stdout


def gh_json(*args):
    out = gh(*args)
    try:
        return json.loads(out)
    except ValueError:
        raise CliError("gh %s returned invalid JSON" % " ".join(args[:2]))


def fetch_issue(repo, number, fields=FEATURE_FIELDS):
    return transport().view_issue(repo, number, fields)


def split_repo(repo, what="registry repo"):
    if "/" not in repo:
        raise CliError("%s must be owner/name, got %r" % (what, repo))
    return repo.split("/", 1)


class GhTransport:
    """Shell out to `gh`; the default on hosts that hold a GitHub credential."""

    name = "gh"

    def list_issues(self, repo, state="open", limit=500):
        return gh_json(
            "issue", "list", "--repo", repo,
            "--state", state,
            "--json", FEATURE_FIELDS, "--limit", str(limit),
        )

    def view_issue(self, repo, number, fields=FEATURE_FIELDS):
        return gh_json("issue", "view", str(number), "--repo", repo, "--json", fields)

    def feature_graph(self, repo, number):
        owner, name = split_repo(repo)
        out = gh(
            "api",
            "graphql",
            "-F",
            "owner=%s" % owner,
            "-F",
            "name=%s" % name,
            "-F",
            "number=%d" % int(number),
            "-f",
            "query=%s" % FEATURE_GRAPH_QUERY,
        )
        try:
            payload = json.loads(out)
        except ValueError:
            raise CliError("gh api graphql returned an unexpected payload")
        return feature_graph_issue(payload, repo, number)

    def edit_labels(self, repo, number, add=(), remove=()):
        if not add and not remove:
            return
        command = ["issue", "edit", str(number), "--repo", repo]
        for name in add:
            command += ["--add-label", name]
        for name in remove:
            command += ["--remove-label", name]
        gh(*command)

    def close_issue(self, repo, number):
        gh("issue", "close", str(number), "--repo", repo)

    def create_issue(self, repo, title, body, labels=(), parent=None, blocked_by=()):
        command = ["issue", "create", "--repo", repo, "--title", title, "--body", body]
        for label in labels:
            command += ["--label", label]
        if parent is not None:
            command += ["--parent", str(parent)]
        if blocked_by:
            command += ["--blocked-by", ",".join(str(number) for number in blocked_by)]
        return gh(*command)

    def comment(self, repo, number, body=None, editor=False, body_file=False):
        command = ["issue", "comment", str(number), "--repo", repo]
        if editor:
            command += ["--editor"]
            return gh(*command)
        if body_file:
            # Long review notes go over stdin, exactly as before.
            return gh(*command, "--body-file", "-", input=body)
        return gh(*command, "--body", body)

    def create_hook(self, repo, body):
        out = gh(
            "api",
            "repos/%s/hooks" % repo,
            "-X",
            "POST",
            "--input",
            "-",
            input=json.dumps(body),
        )
        try:
            return json.loads(out)
        except ValueError:
            raise CliError("gh api repos/%s/hooks returned invalid JSON" % repo)


def broker_base(env=None):
    env = os.environ if env is None else env
    url = (env.get("BROKER_URL") or "").strip()
    if not url:
        raise CliError(
            "SDLC_TRANSPORT=broker needs BROKER_URL (e.g. http://broker:8080)"
        )
    return url.rstrip("/")


class BrokerTransport:
    """GitHub's REST API through the broker's path proxy.

    The broker injects the GitHub App bearer, so the client sends no token and
    must never add one: an Authorization header here would shadow the app's.
    """

    name = "broker"
    timeout = 60

    def __init__(self, base):
        self.base = base

    @classmethod
    def from_env(cls, env=None):
        return cls(broker_base(env) + BROKER_PATH)

    def call(self, method, path, body=None, query=None):
        url = self.base + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        data = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"Accept": "application/vnd.github+json"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            raise CliError(
                "broker %s %s failed: HTTP %d: %s"
                % (method, path, exc.code, http_error_detail(exc))
            )
        except urllib.error.URLError as exc:
            raise CliError("broker %s %s failed: %s" % (method, path, exc.reason))
        except OSError as exc:
            raise CliError("broker %s %s failed: %s" % (method, path, exc))

    def json_call(self, method, path, body=None, query=None):
        raw = self.call(method, path, body=body, query=query)
        try:
            return json.loads(raw) if raw.strip() else None
        except ValueError:
            raise CliError("broker %s %s returned invalid JSON" % (method, path))

    def list_issues(self, repo, state="open", limit=500):
        path = repo_path(repo, "/issues")
        issues = []
        page = 1
        while len(issues) < limit:
            batch = self.json_call(
                "GET", path, query={"state": state, "per_page": PAGE_SIZE, "page": page}
            ) or []
            # gh's issue commands hide pull requests; REST lists them together.
            batch = [item for item in batch if "pull_request" not in item]
            issues.extend(batch)
            if len(batch) < PAGE_SIZE:
                break
            page += 1
        return [self.hydrate(repo, item) for item in issues[:limit]]

    def hydrate(self, repo, data):
        """gh's `--json` payload for one listed issue.

        REST's issue list has no comments or sub-issues field, so features get
        them from their own endpoints; the CLI only reads those fields for
        features, and hydrating every issue would be one request each.
        Blockers are skipped here: nothing that consumes a list result reads
        them, and `sub_tasks` refetches by id when it needs the real graph.
        """
        issue = rest_issue(data)
        if "type:feature" in labels_of(issue):
            number = issue["number"]
            issue["comments"] = self.comments(repo, number)
            tasks = self.sub_issues(repo, number, with_blockers=False)
            issue["subIssues"] = {"nodes": tasks, "totalCount": len(tasks)}
        return issue

    def view_issue(self, repo, number, fields=FEATURE_FIELDS):
        wanted = {name.strip() for name in fields.split(",") if name.strip()}
        number = int(number)
        issue = rest_issue(self.json_call("GET", repo_path(repo, "/issues/%d" % number)))
        if "comments" in wanted:
            issue["comments"] = self.comments(repo, number)
        if "subIssues" in wanted:
            tasks = self.sub_issues(repo, number)
            issue["subIssues"] = {"nodes": tasks, "totalCount": len(tasks)}
        if "blockedBy" in wanted:
            issue["blockedBy"] = {"nodes": self.blocked_by(repo, number)}
        return issue

    def comments(self, repo, number):
        rows = self.json_call("GET", repo_path(repo, "/issues/%d/comments" % number)) or []
        return [
            {
                "author": {"login": (row.get("user") or {}).get("login") or "-"},
                "body": row.get("body") or "",
                "createdAt": row.get("created_at") or "",
            }
            for row in rows
        ]

    def sub_issues(self, repo, number, with_blockers=True):
        rows = self.json_call("GET", repo_path(repo, "/issues/%d/sub_issues" % number)) or []
        tasks = []
        for row in rows:
            task = rest_issue(row)
            if with_blockers:
                # REST has no bulk dependencies view: one call per task.
                task["blockedBy"] = {"nodes": self.blocked_by(repo, task["number"])}
            tasks.append(task)
        return tasks

    def blocked_by(self, repo, number):
        rows = self.json_call(
            "GET", repo_path(repo, "/issues/%d/dependencies/blocked_by" % number)
        ) or []
        return [
            {
                "number": row["number"],
                "title": row.get("title") or "",
                "state": (row.get("state") or "").upper(),
            }
            for row in rows
        ]

    def feature_graph(self, repo, number):
        owner, name = split_repo(repo)
        payload = self.json_call(
            "POST",
            "/graphql",
            body={
                "query": FEATURE_GRAPH_QUERY,
                "variables": {"owner": owner, "name": name, "number": int(number)},
            },
        )
        return feature_graph_issue(payload, repo, number)

    def edit_labels(self, repo, number, add=(), remove=()):
        if add:
            self.json_call(
                "POST",
                repo_path(repo, "/issues/%d/labels" % int(number)),
                body={"labels": list(add)},
            )
        for name in remove:
            self.json_call(
                "DELETE", repo_path(repo, "/issues/%d/labels/%s" % (int(number), path_quote(name)))
            )

    def close_issue(self, repo, number):
        self.json_call(
            "PATCH", repo_path(repo, "/issues/%d" % int(number)), body={"state": "closed"}
        )

    def create_issue(self, repo, title, body, labels=(), parent=None, blocked_by=()):
        created = self.json_call(
            "POST",
            repo_path(repo, "/issues"),
            body={"title": title, "body": body, "labels": list(labels)},
        ) or {}
        if "number" not in created:
            raise CliError("broker POST /repos/%s/issues returned no issue number" % repo)
        number = int(created["number"])
        if parent is not None:
            # REST sub-issues take the parent's issue *id*, not its number.
            if "id" not in created:
                raise CliError("broker POST /repos/%s/issues returned no issue id" % repo)
            self.json_call(
                "POST",
                repo_path(repo, "/issues/%d/sub_issues" % int(parent)),
                body={"sub_issue_id": int(created["id"])},
            )
        for blocker in blocked_by:
            self.json_call(
                "POST",
                repo_path(repo, "/issues/%d/dependencies/blocked_by" % number),
                body={"issue_id": self.issue_id(repo, blocker)},
            )
        url = created.get("html_url") or ""
        if not url:
            raise CliError("broker POST /repos/%s/issues returned no issue URL" % repo)
        # `parse_created_url` reads the number out of this URL, as it does `gh`.
        return url + "\n"

    def issue_id(self, repo, number):
        """REST dependency links name the blocking issue by database id."""
        issue = self.json_call("GET", repo_path(repo, "/issues/%d" % int(number))) or {}
        if "id" not in issue:
            raise CliError("issue #%s not found in %s" % (number, repo))
        return int(issue["id"])

    def comment(self, repo, number, body=None, editor=False, body_file=False):
        # `body_file` is a gh-ism (stdin); the broker sends JSON either way.
        if editor:
            body = edit_message()
            if not body:
                return ""
        posted = self.json_call(
            "POST",
            repo_path(repo, "/issues/%d/comments" % int(number)),
            body={"body": body},
        ) or {}
        return posted.get("html_url") or ""


class HookBrokerTransport(BrokerTransport):
    """`BrokerTransport` bound to the broker's `github-hooks` logical host.

    That host proxies `POST /repos/{owner}/{repo}/hooks` and nothing else: the
    injected installation token carries `repository_hooks: write`, and every
    read, edit or delete is refused. Reusing `call`/`json_call` keeps the URL
    and auth story in one place.
    """

    @classmethod
    def from_env(cls, env=None):
        return cls(broker_base(env) + HOOKS_PATH)

    def create_hook(self, repo, body):
        return self.json_call("POST", repo_path(repo, "/hooks"), body=body) or {}


def transport():
    """The GitHub backend named by $SDLC_TRANSPORT: `gh` unless told otherwise."""
    name = os.environ.get("SDLC_TRANSPORT") or "gh"
    if name == "gh":
        return GhTransport()
    if name == "broker":
        return BrokerTransport.from_env()
    raise CliError(
        "SDLC_TRANSPORT=%r is not a transport; expected 'gh' or 'broker'" % name
    )


def hook_transport():
    """The backend for `sdlc hook`: `gh`, or the broker's github-hooks host."""
    name = os.environ.get("SDLC_TRANSPORT") or "gh"
    if name == "gh":
        return GhTransport()
    if name == "broker":
        return HookBrokerTransport.from_env()
    raise CliError(
        "SDLC_TRANSPORT=%r is not a transport; expected 'gh' or 'broker'" % name
    )


def agent_hook_url(value):
    """The capability URL, or a refusal before the broker can answer 403."""
    url = (value or "").strip()
    if not url.startswith(AGENT_HOOKS_URL) or not url[len(AGENT_HOOKS_URL) :]:
        raise CliError(
            "hook --url must point into %s (got %r); the broker refuses to "
            "register any other URL" % (AGENT_HOOKS_URL, value)
        )
    return url


def hook_events(spec):
    if spec is None:
        return list(DEFAULT_HOOK_EVENTS)
    events = []
    for token in spec.split(","):
        event = token.strip()
        if event and event not in events:
            events.append(event)
    if not events:
        raise CliError("--events needs at least one comma-separated event name")
    return events


def hook_secret(path):
    if not path:
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            secret = handle.read().rstrip("\r\n")
    except OSError as exc:
        raise CliError("cannot read --secret-file %s: %s" % (path, exc.strerror or exc))
    if not secret:
        raise CliError("--secret-file %s is empty" % path)
    return secret


def hook_payload(url, events, secret=None):
    config = {"url": url, "content_type": "json", "insecure_ssl": "0"}
    if secret is not None:
        config["secret"] = secret
    return {"name": "webhook", "active": True, "events": list(events), "config": config}


def path_quote(value):
    return urllib.parse.quote(str(value), safe="")


def repo_path(repo, suffix=""):
    """The api.github.com path for a repo, as the broker proxies it."""
    owner, name = split_repo(repo)
    return "/repos/%s/%s%s" % (path_quote(owner), path_quote(name), suffix)


def rest_issue(data):
    """Project a REST issue onto gh's `--json` shape so parsing is unchanged."""
    return {
        "number": int(data["number"]),
        "title": data.get("title") or "",
        "body": data.get("body") or "",
        "state": (data.get("state") or "").upper(),
        "labels": [
            {"name": entry.get("name")}
            for entry in data.get("labels") or []
            if entry.get("name")
        ],
        "url": data.get("html_url") or "",
    }


def http_error_detail(exc):
    raw = exc.read().decode("utf-8", "replace").strip()
    try:
        message = json.loads(raw).get("message")
    except (ValueError, AttributeError):
        message = None
    return message or raw[:500] or "HTTP %d" % exc.code


def edit_message():
    """Read a comment body from $GIT_EDITOR/$VISUAL/$EDITOR; empty aborts."""
    editor = (
        os.environ.get("GIT_EDITOR")
        or os.environ.get("VISUAL")
        or os.environ.get("EDITOR")
        or "vi"
    )
    with tempfile.TemporaryDirectory(prefix="sdlc-comment-") as tmp:
        path = os.path.join(tmp, "comment.md")
        with open(path, "w"):
            pass
        try:
            proc = subprocess.run(shlex.split(editor) + [path])
        except FileNotFoundError:
            raise CliError("editor not found on PATH: %s" % editor)
        if proc.returncode != 0:
            raise CliError("editor exited %d" % proc.returncode)
        with open(path) as fh:
            return fh.read().rstrip()


def feature_graph_issue(payload, repo, number):
    """Unwrap one GraphQL feature payload into the shape the CLI reads."""
    try:
        issue = payload["data"]["repository"]["issue"]
    except (KeyError, TypeError):
        raise CliError("gh api graphql returned an unexpected payload")
    if not issue:
        raise CliError("issue #%s not found in %s" % (number, repo))
    issue["body"] = issue.get("body") or ""
    issue["labels"] = node_list(issue.get("labels"))
    issue["comments"] = node_list(issue.get("comments"))
    tasks = node_list(issue.get("subIssues"))
    for task in tasks:
        task["labels"] = node_list(task.get("labels"))
    issue["subIssues"] = {"nodes": tasks, "totalCount": len(tasks)}
    return issue


def fetch_feature_graph(repo, number):
    """One GraphQL round trip: the feature, its comments, and its task graph."""
    return transport().feature_graph(repo, number)


def registry_repo():
    return os.environ.get("SDLC_REPO") or DEFAULT_REPO


def node_list(value):
    """GitHub returns {nodes,totalCount}; tolerate plain arrays too."""
    if isinstance(value, dict):
        return value.get("nodes") or []
    return value or []


def labels_of(issue):
    return {entry.get("name") for entry in issue.get("labels") or [] if entry.get("name")}


def lifecycle_of(issue):
    labels = labels_of(issue)
    for status in ("done", "canceled", "in-progress", "todo"):
        if "status:%s" % status in labels:
            return status
    return None


def display_status(issue):
    status = lifecycle_of(issue)
    if status is None:
        status = "closed" if issue.get("state") == "CLOSED" else "open"
    return status


def repo_names(issue):
    names = sorted(name[len("repo:") :] for name in labels_of(issue) if name.startswith("repo:"))
    return ",".join(names)



DESIGN_HEADER_RE = re.compile(r"(?ms)^## Design[ \t]*\n(.*?)(?=^## |\Z)")
ANNOTATION_PREFIX = "> Sam:"


def design_section(body):
    """Canonical `## Design` content, or None.

    Rules (T1): LF line endings, trailing whitespace stripped, annotation lines
    dropped, leading/trailing blank lines removed, joined with LF, no final
    newline.
    """
    if not body:
        return None
    text = body.replace("\r\n", "\n").replace("\r", "\n")
    match = DESIGN_HEADER_RE.search(text)
    if not match:
        return None
    lines = [line.rstrip() for line in match.group(1).split("\n")]
    lines = [line for line in lines if not line.lstrip().startswith(ANNOTATION_PREFIX)]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def design_hash(body):
    section = design_section(body)
    if section is None:
        return None
    return hashlib.sha256(section.encode("utf-8")).hexdigest()


def approval_comment(issue):
    # Exact match only: review text can quote an approval, and a substring match
    # would let it re-point the approved hash.
    for comment in reversed(issue.get("comments") or []):
        body = (comment.get("body") or "").strip()
        match = HASH_RE.fullmatch(body)
        if match:
            return match.group(1), comment
    return None, None


def approval_state(issue):
    """needs-reapproval beats approved; a missing hash is not approval."""
    current = design_hash(issue.get("body"))
    approved, comment = approval_comment(issue)
    labels = labels_of(issue)
    if current is None:
        return Approval("missing", current, approved, comment, "no '## Design' section")
    if "status:needs-reapproval" in labels:
        return Approval("stale", current, approved, comment, "status:needs-reapproval")
    if "status:approved" not in labels:
        return Approval("missing", current, approved, comment, "no status:approved label")
    if approved is None:
        return Approval("missing", current, approved, comment, "approved without a sha256 comment")
    if approved != current:
        return Approval("stale", current, approved, comment, "design changed since approval")
    return Approval("approved", current, approved, comment, "")


def comment_author(comment):
    if not comment:
        return "-"
    return (comment.get("author") or {}).get("login") or "-"


def comment_date(comment):
    if not comment:
        return "-"
    return comment.get("createdAt") or "-"




def feature_issues(repo, all_states=False):
    issues = transport().list_issues(
        repo, state="all" if all_states else "open", limit=500
    )
    features = []
    for issue in issues:
        if "type:feature" not in labels_of(issue):
            continue
        # Label writes can lag the index ~15s; decide client-side instead of
        # trusting a server-side --label filter.
        if not all_states and (
            issue.get("state") == "CLOSED" or lifecycle_of(issue) in TERMINAL
        ):
            continue
        features.append(issue)
    return features


def resolve_number(repo, ref):
    if ref is None:
        raise CliError("a feature number or title is required")
    if str(ref).isdigit():
        return int(ref)
    needle = str(ref).lower()
    matches = [
        feature
        for feature in feature_issues(repo, all_states=True)
        if needle in (feature.get("title") or "").lower()
    ]
    if not matches:
        raise CliError("no feature matches %r" % ref)
    if len(matches) > 1:
        listing = ", ".join("#%d %s" % (feature["number"], feature["title"]) for feature in matches)
        raise CliError("%r is ambiguous: %s" % (ref, listing))
    return matches[0]["number"]


def resolve_feature(repo, ref):
    if str(ref).isdigit():
        return fetch_issue(repo, int(ref))
    return fetch_issue(repo, resolve_number(repo, ref))


def open_blockers(task):
    return [node for node in node_list(task.get("blockedBy")) if node.get("state") == "OPEN"]


def task_state(task):
    if task.get("state") == "CLOSED":
        return "closed"
    if open_blockers(task):
        return "blocked"
    status = lifecycle_of(task)
    return "ready" if status == "todo" else status or "open"


def sub_tasks(repo, feature):
    nodes = node_list(feature.get("subIssues"))
    if all("blockedBy" in node for node in nodes):
        return nodes
    return [fetch_issue(repo, node["number"], TASK_FIELDS) for node in nodes]


def task_counts(tasks):
    open_count = ready = blocked = 0
    for task in tasks:
        state = task_state(task)
        open_count += task.get("state") != "CLOSED"
        ready += state == "ready"
        blocked += state == "blocked"
    return open_count, ready, blocked




def pick(candidates, header="sdlc features"):
    """tv, then fzf, then a numbered prompt. Returns one candidate line.

    Only stdout is captured: both TUIs paint on stderr, so capturing that
    hides the interface while they wait for keys.
    """
    if not candidates:
        raise CliError("nothing to pick")
    if shutil.which("tv"):
        handle, path = tempfile.mkstemp(prefix="sdlc-", suffix=".txt")
        try:
            with os.fdopen(handle, "w") as fh:
                fh.write("\n".join(candidates) + "\n")
            proc = subprocess.run(
                [
                    "tv",
                    "--source-command",
                    "cat %s" % shlex.quote(path),
                    "--no-preview",
                    "--input-header",
                    header,
                ],
                stdout=subprocess.PIPE,
                text=True,
            )
        finally:
            os.unlink(path)
    elif shutil.which("fzf"):
        proc = subprocess.run(
            ["fzf", "--delimiter", "\t", "--with-nth", "1,2,3,4"],
            input="\n".join(candidates) + "\n",
            stdout=subprocess.PIPE,
            text=True,
        )
    else:
        for index, candidate in enumerate(candidates, 1):
            sys.stderr.write("  %d) %s\n" % (index, candidate))
        sys.stderr.write("pick: ")
        sys.stderr.flush()
        answer = sys.stdin.readline().strip()
        if not answer:
            raise CliError("no selection")
        if answer.isdigit() and 1 <= int(answer) <= len(candidates):
            return candidates[int(answer) - 1]
        for candidate in candidates:
            if answer in candidate:
                return candidate
        raise CliError("no matching selection: %s" % answer)
    if proc.returncode != 0 or not proc.stdout.strip():
        raise CliError("selection canceled")
    return proc.stdout.splitlines()[0]


def summary(feature):
    """The number/title/status/repo projection every list format shares."""
    return (
        feature["number"],
        one_line(feature.get("title") or ""),
        display_status(feature),
        repo_names(feature),
    )


def path_row(issue):
    number, title, status, repo = summary(issue)
    return "\t".join([str(number), title, status, clean(repo or "-")])


def preview_text(feature):
    number, title, status, repo = summary(feature)
    return "#%d %s\n[%s] %s\n\n%s\n" % (
        number,
        title,
        status,
        repo or "-",
        clean(feature.get("body") or ""),
    )


def excerpt(value, lines=20, chars=1600):
    """Truncate untrusted body text to a preview-sized excerpt."""
    text = clean(value or "").strip("\n")
    if not text.strip():
        return "(none)"
    rows = text.split("\n")
    kept = rows[:lines]
    clipped = len(rows) > lines
    out = "\n".join(kept)
    if len(out) > chars:
        out = out[:chars].rstrip()
        clipped = True
    return out + "\n…" if clipped else out


def feature_facts(feature):
    approval = approval_state(feature)
    return [
        "labels: %s" % (", ".join(sorted(labels_of(feature))) or "(none)"),
        "approval: %s (%s)"
        % (approval.state, clean(approval.reason) or "design matches"),
        "design sha256: %s" % ((approval.design or "-")[:12]),
    ]


def task_lines(feature):
    tasks = node_list(feature.get("subIssues"))
    open_tasks = [task for task in tasks if task.get("state") != "CLOSED"]
    return [
        "sub-issues: %d open of %d" % (len(open_tasks), len(tasks)),
    ] + [
        "  #%d [%s] %s"
        % (
            task["number"],
            "open" if task.get("state") != "CLOSED" else "closed",
            one_line(task.get("title") or ""),
        )
        for task in tasks[:8]
    ]


def action_preview(feature, action):
    """Describe one action against a feature, from local payload data only."""
    lines = [
        "#%d %s" % (feature["number"], one_line(feature.get("title") or "")),
        "[%s] %s" % (display_status(feature), repo_names(feature) or "-"),
        "",
        "## %s" % action,
        "%s: %s." % (action.capitalize(), ACTION_HELP[action]),
    ]
    if action in ("complete", "cancel"):
        lines += [
            "",
            "WARNING: this is terminal — #%d becomes %s and there is no reopen "
            "flow. Confirms with y/N before writing."
            % (feature["number"], "done" if action == "complete" else "canceled"),
        ]
    if action in ("show", "review"):
        lines += ["", "### body", excerpt(feature.get("body"))]
        comments = feature.get("comments") or []
        if action == "show" and comments:
            lines += [
                "",
                "### latest comment (%s)" % clean(comment_author(comments[-1])),
                excerpt((comments[-1].get("body") or ""), lines=6, chars=400),
            ]
    elif action == "status":
        lines += ["", "### state"] + feature_facts(feature) + task_lines(feature)
    elif action == "next":
        lines += ["", "### tasks"] + task_lines(feature)
    elif action == "approve":
        approval = approval_state(feature)
        lines += ["", "### approval"] + feature_facts(feature) + [
            "approved sha256: %s" % (approval.approved or "-"),
        ]
    return "\n".join(lines) + "\n"


def write_picker_channel(tmp, name, rows, previews, display, output="{split:\\t:0}"):
    """Write a tv channel whose previews are precomputed files, with no live gh calls.

    The preview command is a bare `cat` so it never blocks on the network; tv
    resolves {split:\t:0} from the row to choose the file.
    """
    cable = os.path.join(tmp, "cable")
    previews_dir = os.path.join(tmp, "previews")
    os.makedirs(cable)
    os.makedirs(previews_dir)
    source = os.path.join(tmp, "%s.tsv" % name)
    with open(source, "w") as fh:
        fh.write("\n".join(rows) + "\n")
    for key, text in previews.items():
        with open(os.path.join(previews_dir, "%s.md" % key), "w") as fh:
            fh.write(text)
    preview = "cat %s/{split:\\t:0}.md" % shlex.quote(previews_dir)
    channel = (
        '[metadata]\nname = "%s"\nrequirements = ["sdlc"]\n\n'
        '[source]\ncommand = "cat %s"\nentry_delimiter = "\\n"\n'
        'display = "%s"\n'
        'output = "%s"\n\n'
        '[preview]\ncommand = "%s"\n'
    ) % (name, shlex.quote(source), display, output, preview)
    with open(os.path.join(cable, "%s.toml" % name), "w") as fh:
        fh.write(channel)
    return cable


def write_picker_cable(tmp, features):
    """Write the feature list and its previews for tv, with no live gh calls."""
    return write_picker_channel(
        tmp,
        "sdlc-features",
        [path_row(feature) for feature in features],
        {str(feature["number"]): preview_text(feature) for feature in features},
        display="#{split:\\t:0} #{split:\\t:1} [#{split:\\t:2}] {split:\\t:3}",
    )




def parse_revdiff_annotations(text):
    """Parse revdiff's `## file:line (type)` records into anchored notes."""
    notes = []
    current = None
    for raw in (text or "").split("\n"):
        note_match = REVDIFF_NOTE_RE.match(raw)
        file_match = None if note_match else REVDIFF_FILE_RE.match(raw)
        if note_match or file_match:
            parsed = note_match or file_match
            current = {
                "file": parsed.group("file"),
                "start": int(note_match.group("start")) if note_match else None,
                "end": int(note_match.group("end")) if note_match and note_match.group("end") else None,
                "lines": [],
            }
            notes.append(current)
        elif current is not None:
            # revdiff prefixes body lines that would look like a record header.
            escaped = raw.startswith(" ") and raw[1:].lstrip(" ").startswith("## ")
            current["lines"].append(raw[1:] if escaped else raw)
    for note in notes:
        lines = note["lines"]
        while lines and not lines[-1].strip():
            lines.pop()
        note["text"] = "\n".join(line.rstrip() for line in lines).strip()
    return [
        ReviewNote(note["file"], note["start"], note["end"], note["text"])
        for note in notes
    ]


def review_quote(note, body_lines, limit=20):
    """Quote the reviewed body lines; anchors are advisory, the quote is exact."""
    if not note.start:
        return None
    start = max(note.start, 1)
    end = min(note.end or start, len(body_lines))
    if start > end:
        return None
    picked = body_lines[start - 1 : end][:limit]
    quoted = "\n".join("> " + clean(line) for line in picked)
    if end - start + 1 > limit:
        quoted += "\n> …"
    return quoted


def review_marker(feature_number, note, body_lines=None):
    # Hash the quoted text, not the temp path: stable across line shifts, re-posted when the text changes.
    quote = review_quote(note, body_lines) if body_lines is not None else None
    digest = hashlib.sha256(
        ("%s\n%s" % (note.text.strip(), quote or "")).encode("utf-8")
    ).hexdigest()[:12]
    return "<!-- sdlc-review:n%d:%s -->" % (feature_number, digest)


def render_review(feature_number, title, body, notes, markers=()):
    body_lines = body.split("\n")
    kept = []
    seen = set(markers)
    for note in notes:
        marker = review_marker(feature_number, note, body_lines)
        if marker in seen:
            continue
        seen.add(marker)
        kept.append((note, marker))
    if not kept:
        return ""
    digest = design_hash(body)
    header = "## Review — #%d %s (design sha256:%s)" % (
        feature_number,
        one_line(title),
        digest[:12] if digest else "none",
    )
    blocks = []
    for note, marker in kept:
        if note.start and note.end and note.end != note.start:
            location = "lines %d–%d" % (note.start, note.end)
        elif note.start:
            location = "line %d" % note.start
        else:
            location = "file"
        block = [marker, "### %s" % location]
        quote = review_quote(note, body_lines)
        if quote:
            block += ["", quote]
        block += ["", clean(note.text)]
        blocks.append("\n".join(block))
    return "\n\n".join([header] + blocks) + "\n"




def cwd_repo_name(cwd=None):
    def run(*args):
        return subprocess.run(
            ["git", *args], cwd=cwd, capture_output=True, text=True
        )

    try:
        proc = run("remote", "get-url", "origin")
        if proc.returncode == 0 and proc.stdout.strip():
            name = re.sub(r"\.git$", "", proc.stdout.strip().rstrip("/"))
            name = re.split(r"[/:]", name)[-1]
            if name:
                return name
        proc = run("rev-parse", "--show-toplevel")
    except FileNotFoundError:
        return None
    if proc.returncode != 0:
        return None
    return os.path.basename(proc.stdout.strip()) or None


def pick_action(feature=None):
    """Pick an action. With a feature, each action previews what it will do.

    The feature payload is already in hand (or fetched once by cmd_ui), so the
    previews are precomputed files read by `cat`; the picker never runs gh.
    """
    if feature is None or not shutil.which("tv"):
        return pick(list(ACTIONS), header="sdlc actions").strip()
    rows = ["%s\t%s" % (action, ACTION_HELP[action]) for action in ACTIONS]
    with tempfile.TemporaryDirectory(prefix="sdlc-cable-") as tmp:
        cable = write_picker_channel(
            tmp,
            "sdlc-actions",
            rows,
            {action: action_preview(feature, action) for action in ACTIONS},
            display="#{split:\\t:0} {split:\\t:1}",
        )
        proc = subprocess.run(
            ["tv", "--cable-dir", cable, "sdlc-actions"],
            stdout=subprocess.PIPE,
            text=True,
        )
    if proc.returncode != 0 or not proc.stdout.strip():
        raise CliError("selection canceled")
    return proc.stdout.splitlines()[0].strip()


def pick_feature(repo, all_states=False, features=None):
    if features is None:
        features = feature_issues(repo, all_states=all_states)
    if not features:
        raise CliError("no active features in %s" % repo)
    cwd = cwd_repo_name()
    features.sort(key=lambda feature: 0 if cwd and cwd in repo_names(feature) else 1)
    rows = [path_row(feature) for feature in features]
    if not shutil.which("tv"):
        return int(pick(rows).split("\t")[0])

    with tempfile.TemporaryDirectory(prefix="sdlc-cable-") as tmp:
        cable = write_picker_cable(tmp, features)
        proc = subprocess.run(
            ["tv", "--cable-dir", cable, "sdlc-features"],
            stdout=subprocess.PIPE,
            text=True,
        )
    if proc.returncode != 0 or not proc.stdout.strip():
        raise CliError("selection canceled")
    selected = proc.stdout.splitlines()[0].strip()
    try:
        return int(selected)
    except ValueError:
        raise CliError("unexpected picker output: %r" % selected)


def confirm(prompt):
    sys.stderr.write("%s? [y/N] " % prompt)
    sys.stderr.flush()
    return sys.stdin.readline().strip().lower() in ("y", "yes")




def cmd_list(args):
    repo = args.repo or registry_repo()
    features = feature_issues(repo, all_states=args.all)
    if args.pick:
        print(pick([path_row(feature) for feature in features]).split("\t")[0])
        return
    if args.format == "path":
        for feature in features:
            print(path_row(feature))
        return
    if args.format == "json":
        rows = []
        for feature in features:
            number, title, status, repo = summary(feature)
            rows.append(
                {
                    "number": number,
                    "title": title,
                    "status": status,
                    "repo": repo,
                    "state": feature.get("state"),
                    "approval": approval_state(feature).state,
                    "url": feature.get("url"),
                }
            )
        print(json.dumps(rows, indent=2))
        return
    for feature in features:
        labels = labels_of(feature)
        status = display_status(feature)
        if "status:needs-reapproval" in labels:
            status += "+needs-reapproval"
        elif "status:approved" in labels:
            status += "+approved"
        print(
            "#%d [%s] %s %s"
            % (
                feature["number"],
                status,
                repo_names(feature) or "-",
                one_line(feature.get("title") or ""),
            )
        )


def cmd_show(args):
    repo = registry_repo()
    feature = resolve_feature(repo, args.feature)
    print(clean(feature.get("body") or ""))
    print("\n--- comments ---")
    comments = feature.get("comments") or []
    if not comments:
        print("(no comments)")
    for comment in comments:
        print(
            "\n[%s @ %s]\n%s"
            % (
                clean(comment_author(comment)),
                clean(comment_date(comment)),
                clean((comment.get("body") or "").strip()),
            )
        )


def cmd_status(args):
    repo = registry_repo()
    feature = fetch_feature_graph(repo, resolve_number(repo, args.feature))
    approval = approval_state(feature)
    tasks = sub_tasks(repo, feature)
    open_count, ready_count, blocked_count = task_counts(tasks)
    print("#%d %s" % (feature["number"], one_line(feature.get("title") or "")))
    print("state=%s labels=%s" % (feature.get("state"), one_line(",".join(sorted(labels_of(feature))))))
    print("design_sha256=%s" % (approval.design or "-"))
    print("approved_sha256=%s" % (approval.approved or "-"))
    print("approved_by=%s" % clean(comment_author(approval.comment)))
    print("approved_at=%s" % clean(comment_date(approval.comment)))
    print("approval=%s" % approval.state)
    if approval.state == "stale":
        print("WARN: design no longer matches the approval; re-approval required (%s)" % clean(approval.reason))
    elif approval.state == "missing":
        print("WARN: no recorded approval (%s)" % clean(approval.reason))
    print("tasks: open=%d ready=%d blocked=%d" % (open_count, ready_count, blocked_count))
    for task in tasks:
        state = task_state(task)
        blockers = open_blockers(task)
        suffix = " blocked_by=%s" % [node["number"] for node in blockers] if blockers else ""
        print("  #%d [%s] %s%s" % (task["number"], state, one_line(task.get("title") or ""), suffix))


def next_feature(repo, ref, do_pick):
    if ref is not None:
        return resolve_feature(repo, ref)
    features = feature_issues(repo, all_states=False)
    if not features:
        raise CliError("no active features in %s" % repo)
    if do_pick:
        chosen = pick([path_row(feature) for feature in features])
        return fetch_issue(repo, int(chosen.split("\t")[0]))
    return fetch_issue(repo, features[0]["number"])


def cmd_next(args):
    repo = registry_repo()
    if args.feature is not None:
        number = resolve_number(repo, args.feature)
    else:
        features = feature_issues(repo, all_states=False)
        if not features:
            raise CliError("no active features in %s" % repo)
        number = pick_feature(repo, features=features) if args.pick else features[0]["number"]
    feature = fetch_feature_graph(repo, number)
    approval = approval_state(feature)
    if approval.state == "stale":
        raise CliError(
            "#%d design changed since approval (now sha256:%s, approved %s); "
            "re-approval required: sdlc approve %d"
            % (
                feature["number"],
                (approval.design or "-")[:12],
                (approval.approved or "missing")[:12],
                feature["number"],
            )
        )
    if approval.state != "approved":
        raise CliError(
            "#%d is not approved (%s); ask the human, then run "
            "'sdlc approve %d'" % (feature["number"], approval.reason, feature["number"])
        )
    tasks = sub_tasks(repo, feature)
    ready = [task for task in tasks if task_state(task) == "ready"]
    if ready:
        task = ready[0]
        print("#%d %s  (feature #%d)" % (task["number"], one_line(task.get("title") or ""), feature["number"]))
        return
    open_tasks = [task for task in tasks if task.get("state") != "CLOSED"]
    blocked = [
        "  #%d is blocked by %s"
        % (task["number"], ", ".join("#%d" % node["number"] for node in open_blockers(task)))
        for task in open_tasks
        if open_blockers(task)
    ]
    if blocked:
        raise CliError("no ready tasks for #%d\n%s" % (feature["number"], "\n".join(blocked)))
    if not open_tasks:
        raise CliError("no ready tasks for #%d: no open tasks" % feature["number"])
    raise CliError("no ready tasks for #%d: no task is status:todo" % feature["number"])


def cmd_approve(args):
    if not args.yes and not sys.stdin.isatty():
        raise CliError("approve requires a TTY; pass --yes for a non-interactive approval")
    repo = registry_repo()
    feature = next_feature(repo, args.feature, args.pick)
    if "type:feature" not in labels_of(feature):
        raise CliError("#%d is not a feature (missing type:feature); refusing to approve" % feature["number"])
    digest = design_hash(feature.get("body"))
    if digest is None:
        raise CliError("#%d has no '## Design' section; refusing to approve" % feature["number"])
    prompts = (
        "approve #%d %r design sha256:%s? [y/N] "
        % (feature["number"], one_line(feature.get("title") or ""), digest)
    )
    if not args.yes:
        sys.stderr.write(prompts)
        sys.stderr.flush()
        answer = sys.stdin.readline().strip().lower()
        if answer not in ("y", "yes"):
            raise CliError("not approved")
    remove = ["status:needs-reapproval"] if "status:needs-reapproval" in labels_of(feature) else []
    backend = transport()
    backend.edit_labels(repo, feature["number"], add=["status:approved"], remove=remove)
    backend.comment(repo, feature["number"], body="Approved design sha256:%s" % digest)
    print("approved #%d sha256:%s" % (feature["number"], digest))


def parse_created_url(output):
    # `gh issue create` has no --json; the printed URL is the only handle. The
    # broker transport prints the same URL from the REST response.
    match = re.search(r"https?://\S+/issues/(\d+)", output)
    if match is None:
        raise CliError("could not parse the issue URL from gh output: %r" % output.strip())
    return int(match.group(1)), match.group(0)


def cmd_new(args):
    name = split_repo(args.repo, "--repo")[1]
    title = args.title or args.slug.replace("-", " ")
    body = "## Design\n\nPending.\n\n## Plan\n\n- [ ] T1: Scope the design\n"
    output = transport().create_issue(
        registry_repo(),
        title,
        body,
        labels=["type:feature", "repo:%s" % name, "status:todo"],
    )
    number, url = parse_created_url(output)
    print("#%d %s" % (number, url))


def task_number_map(repo, feature):
    """Map T-labels to issue numbers from the plan body and sub-issue titles."""
    mapping = {}
    for line in (feature.get("body") or "").splitlines():
        match = re.match(r"\s*-\s*\[[ xX]\]\s*(T\d+)\b.*?#(\d+)", line)
        if match:
            mapping[match.group(1).upper()] = int(match.group(2))
    for node in node_list(feature.get("subIssues")):
        title = node.get("title")
        if not title:
            title = fetch_issue(repo, node["number"], NODE_FIELDS).get("title") or ""
        match = re.match(r"\s*(T\d+)\b", title)
        label = match.group(1).upper() if match else None
        if label and label not in mapping:
            mapping[label] = node["number"]
    return mapping


def resolve_needs(repo, feature, needs):
    tokens = [token.strip() for token in (needs or "").split(",") if token.strip()]
    if not tokens:
        return []
    numbers = []
    mapping = None
    for token in tokens:
        direct = re.fullmatch(r"#?(\d+)", token)
        if direct:
            numbers.append(int(direct.group(1)))
            continue
        label = re.fullmatch(r"[Tt](\d+)", token)
        if label:
            if mapping is None:
                mapping = task_number_map(repo, feature)
            key = "T%s" % label.group(1)
            if key in mapping:
                numbers.append(mapping[key])
                continue
        raise CliError("cannot resolve --needs token %r for #%d" % (token, feature["number"]))
    return numbers


def cmd_task_add(args):
    repo = registry_repo()
    feature = resolve_feature(repo, args.feature)
    blocked = resolve_needs(repo, feature, args.needs)
    output = transport().create_issue(
        repo,
        args.title,
        "Part of #%d." % feature["number"],
        labels=["status:todo"],
        parent=feature["number"],
        blocked_by=blocked,
    )
    number, url = parse_created_url(output)
    print("#%d %s" % (number, url))


TASK_TRANSITIONS = {
    "start": ("status:in-progress", ("status:todo",)),
    "done": ("status:done", ("status:todo", "status:in-progress")),
    "cancel": ("status:canceled", ("status:done", "status:todo", "status:in-progress")),
}


def set_status(repo, number, add, remove, close):
    issue = fetch_issue(repo, number, NODE_FIELDS)
    labels = labels_of(issue)
    transport().edit_labels(
        repo, number, add=[add], remove=[name for name in remove if name in labels]
    )
    if close:
        transport().close_issue(repo, number)


def cmd_task_transition(action):
    def run(args):
        repo = registry_repo()
        if not str(args.issue).isdigit():
            raise CliError("task %s takes an issue number, got %r" % (action, args.issue))
        add, remove = TASK_TRANSITIONS[action]
        set_status(repo, int(args.issue), add, remove, close=action in ("done", "cancel"))
        print("#%s %s" % (args.issue, add))

    return run


def cmd_feature_transition(terminal):
    def run(args):
        repo = registry_repo()
        if terminal == "done":
            feature = fetch_feature_graph(repo, resolve_number(repo, args.feature))
            open_tasks = [task for task in sub_tasks(repo, feature) if task.get("state") != "CLOSED"]
            if open_tasks:
                raise CliError(
                    "refusing to complete #%d: %d open task(s): %s"
                    % (
                        feature["number"],
                        len(open_tasks),
                        ", ".join("#%d" % task["number"] for task in open_tasks),
                    )
                )
        else:
            feature = resolve_feature(repo, args.feature)
        add = "status:%s" % terminal
        remove = tuple("status:%s" % name for name in ("todo", "in-progress", "done", "canceled") if name != terminal)
        set_status(repo, feature["number"], add, remove, close=True)
        print("#%d %s" % (feature["number"], add))

    return run


def cmd_review(args):
    repo = registry_repo()
    feature = resolve_feature(repo, args.feature)
    body = feature.get("body") or ""
    name = "issue-%d.md" % feature["number"]
    env = {key: value for key, value in os.environ.items() if key != "REVDIFF_OUTPUT"}
    try:
        proc = subprocess.run(
            ["revdiff", "--stdin", "--stdin-name", name, "--no-tree", "--wrap"],
            input=body,
            stdout=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            env=env,
        )
    except FileNotFoundError:
        raise CliError("revdiff not found on PATH")
    if proc.returncode not in (0, 10):
        raise CliError("revdiff exited %d" % proc.returncode)

    notes = parse_revdiff_annotations(proc.stdout)
    anchored = sorted({note.file for note in notes if note.file != name})
    if anchored:
        raise CliError(
            "revdiff anchored to %s, not %s: the body parsed as a diff"
            % (", ".join(anchored), name)
        )
    if not notes:
        print("no review notes (annotate in revdiff, then quit with q)")
        return
    existing = "\n".join(
        clean(comment.get("body") or "") for comment in feature.get("comments") or []
    )
    comment = render_review(
        feature["number"],
        feature.get("title") or "",
        body,
        notes,
        set(REVIEW_MARKER_RE.findall(existing)),
    )
    if not comment:
        print("no new review notes")
        return
    if args.dry_run:
        print(comment, end="")
        return
    url = transport().comment(repo, feature["number"], body=comment, body_file=True)
    print(
        "posted review notes to #%d %s"
        % (feature["number"], url.strip() or "")
    )
    print('tell the agent: read #%d' % feature["number"])


def cmd_comment(args):
    repo = registry_repo()
    ref = args.feature if args.feature is not None else str(pick_feature(repo))
    feature = resolve_feature(repo, ref)
    transport().comment(repo, feature["number"], editor=True)


def cmd_hook_add(args):
    owner, name = split_repo(args.repo, "hook repo")
    if not owner or not name or "/" in name:
        raise CliError("hook repo must be owner/name, got %r" % args.repo)
    url = agent_hook_url(args.url)
    payload = hook_payload(
        url, hook_events(args.events), hook_secret(args.secret_file)
    )
    created = hook_transport().create_hook(args.repo, payload)
    if not isinstance(created, dict) or created.get("id") is None:
        raise CliError("POST /repos/%s/hooks returned no hook id" % args.repo)
    print("created hook %s on %s" % (created["id"], args.repo))
    print(url)


def cmd_ui(args):
    if args.repo:
        os.environ["SDLC_REPO"] = args.repo
    repo = registry_repo()
    features = []
    actions = []
    for token in args.items:
        lowered = token.lower()
        if lowered in ACTIONS:
            actions.append(lowered)
        else:
            features.append(token)
    if len(features) > 1:
        raise CliError("expected at most one feature, got %s" % ", ".join(features))
    if len(actions) > 1:
        raise CliError("expected at most one action, got %s" % ", ".join(actions))

    if features:
        ref = features[0]
        # One fetch, only when the action picker will actually show previews.
        feature = None if actions else resolve_feature(repo, ref)
    else:
        pool = feature_issues(repo, all_states=args.all)
        number = pick_feature(repo, features=pool)
        ref = str(number)
        feature = next((item for item in pool if item["number"] == number), None)
    action = actions[0] if actions else pick_action(feature)
    if action == "show":
        cmd_show(argparse.Namespace(feature=ref))
    elif action == "status":
        cmd_status(argparse.Namespace(feature=ref))
    elif action == "review":
        cmd_review(argparse.Namespace(feature=ref, dry_run=False))
    elif action == "comment":
        cmd_comment(argparse.Namespace(feature=ref))
    elif action == "next":
        cmd_next(argparse.Namespace(feature=ref, pick=False))
    elif action == "approve":
        cmd_approve(argparse.Namespace(feature=ref, pick=False, yes=False))
    elif action in ("complete", "cancel"):
        if confirm("%s #%s" % (action, ref)):
            cmd_feature_transition("done" if action == "complete" else "canceled")(
                argparse.Namespace(feature=ref)
            )
        else:
            print("not %s" % ("completed" if action == "complete" else "canceled"))
    else:
        raise CliError("unknown action %r" % action)




def feature_arg(parser, required=True, help_text="issue number or title substring"):
    parser.add_argument("feature", nargs=None if required else "?", help=help_text)


def pick_arg(parser, help_text="pick an active feature"):
    parser.add_argument("--pick", action="store_true", help=help_text)


def all_arg(parser, help_text="include terminal features"):
    parser.add_argument("--all", action="store_true", help=help_text)


def build_parser():
    parser = argparse.ArgumentParser(
        prog="sdlc",
        description="Stateless SDLC control plane over GitHub Issues (registry: $SDLC_REPO).",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("list", help="list features")
    all_arg(p, "include closed, done, and canceled")
    p.add_argument("--repo", help="registry repo (default $SDLC_REPO)")
    p.add_argument("--format", choices=("human", "path", "json"), default="human")
    pick_arg(p, "pick one feature and print its number")
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("show", help="print a feature body and comments")
    feature_arg(p)
    p.set_defaults(fn=cmd_show)

    p = sub.add_parser("status", help="approval and task state of a feature")
    feature_arg(p)
    p.set_defaults(fn=cmd_status)

    p = sub.add_parser("next", help="print the next ready task")
    feature_arg(p, required=False)
    pick_arg(p)
    p.set_defaults(fn=cmd_next)

    p = sub.add_parser("approve", help="record human approval of the design")
    feature_arg(p, required=False)
    p.add_argument("--yes", action="store_true", help="skip the TTY confirmation")
    pick_arg(p)
    p.set_defaults(fn=cmd_approve)

    p = sub.add_parser("new", help="create a feature issue")
    p.add_argument("slug")
    p.add_argument("--repo", required=True, help="code repo the feature belongs to")
    p.add_argument("--title")
    p.set_defaults(fn=cmd_new)

    task = sub.add_parser("task", help="manage task sub-issues")
    task_sub = task.add_subparsers(dest="task_command", required=True)
    p = task_sub.add_parser("add", help="create a task sub-issue")
    feature_arg(p, help_text="feature issue number or title substring")
    p.add_argument("title")
    p.add_argument("--needs", help="comma-separated T-labels or issue numbers")
    p.set_defaults(fn=cmd_task_add)
    for action, help_text in (
        ("start", "mark a task in progress"),
        ("done", "mark a task done and close it"),
        ("cancel", "cancel a task and close it"),
    ):
        p = task_sub.add_parser(action, help=help_text)
        p.add_argument("issue")
        p.set_defaults(fn=cmd_task_transition(action))

    p = sub.add_parser("complete", help="close a feature as done")
    feature_arg(p)
    p.set_defaults(fn=cmd_feature_transition("done"))

    p = sub.add_parser("cancel", help="close a feature as canceled")
    feature_arg(p)
    p.set_defaults(fn=cmd_feature_transition("canceled"))

    p = sub.add_parser("ui", help="pick a feature and an action")
    p.add_argument("items", nargs="*", help="action and/or feature")
    all_arg(p)
    p.add_argument("--repo", help="registry repo (default $SDLC_REPO)")
    p.set_defaults(fn=cmd_ui)

    p = sub.add_parser("review", help="review a feature body in revdiff and post the notes")
    feature_arg(p)
    p.add_argument("--dry-run", action="store_true", help="print the comment instead of posting")
    p.set_defaults(fn=cmd_review)

    p = sub.add_parser("comment", help="comment on a feature in $EDITOR")
    feature_arg(p, required=False)
    p.set_defaults(fn=cmd_comment)

    hook = sub.add_parser(
        "hook",
        help="register a GitHub repository webhook",
        description=(
            "Register a repo webhook with the agent hook receiver. Creation is "
            "the only operation: the broker's github-hooks host proxies POST "
            "/repos/OWNER/REPO/hooks alone and refuses list, edit and delete."
        ),
    )
    hook_sub = hook.add_subparsers(dest="hook_command", required=True)
    p = hook_sub.add_parser(
        "add",
        help="register a webhook pointing at the agent receiver",
        description=(
            "--url must sit under %s; the broker refuses any other URL, so the "
            "CLI rejects it before sending. There is no list or delete: the "
            "broker does not proxy them." % AGENT_HOOKS_URL
        ),
    )
    p.add_argument("repo", help="owner/name of the repo to register the hook on")
    p.add_argument(
        "--url", required=True, help="capability URL under %s" % AGENT_HOOKS_URL
    )
    p.add_argument(
        "--events",
        help="comma-separated event names (default: %s)"
        % ",".join(DEFAULT_HOOK_EVENTS),
    )
    p.add_argument(
        "--secret-file",
        help="file whose contents become the webhook secret (sent, never printed)",
    )
    p.set_defaults(fn=cmd_hook_add)

    return parser


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    # A bare `sdlc` is the human entry point: the picker.
    args = build_parser().parse_args(argv or ["ui"])
    try:
        args.fn(args)
    except CliError as exc:
        sys.stderr.write("%s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
