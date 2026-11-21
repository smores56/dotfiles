"""CLI tests against a fake `gh` on PATH that records every call and serves canned JSON."""

import importlib
import json
import os
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest import mock

from support import COMMENT_AT, DESIGN, DESIGN_SHA, MODULE_DIR, run_cli, write_script

import sdlc_issues

FAKE_GH = '''#!{python}
import json, os, sys

state = os.environ["FAKE_GH_STATE"]
args = sys.argv[1:]
with open(os.path.join(state, "calls.jsonl"), "a") as fh:
    fh.write(json.dumps(args) + "\\n")

def read(name):
    path = os.path.join(state, name)
    if not os.path.exists(path):
        sys.stderr.write("fake gh: no canned response for %s\\n" % name)
        sys.exit(3)
    with open(path) as fh:
        return fh.read()

if args[:2] == ["issue", "list"]:
    sys.stdout.write(read("list.json"))
elif args[:2] == ["issue", "view"]:
    sys.stdout.write(read("issue-%s.json" % args[2]))
elif args[:2] == ["issue", "create"]:
    sys.stdout.write(read("create_url.txt"))
elif args[:2] == ["issue", "edit"]:
    # Dependency and title edits rewrite the canned issue, so a later read
    # sees what GitHub would hold.
    path = os.path.join(state, "issue-%s.json" % args[2])
    if os.path.exists(path):
        with open(path) as fh:
            iss = json.load(fh)
        for index, arg in enumerate(args):
            if arg == "--title":
                iss["title"] = args[index + 1]
        blocked = list((iss.get("blockedBy") or {}).get("nodes") or [])
        for index, arg in enumerate(args):
            if arg == "--add-blocked-by":
                for number in str(args[index + 1]).split(","):
                    if not any(node["number"] == int(number) for node in blocked):
                        blocked.append({"number": int(number), "title": "", "state": "OPEN"})
            elif arg == "--remove-blocked-by":
                for number in str(args[index + 1]).split(","):
                    blocked = [node for node in blocked if node["number"] != int(number)]
        iss["blockedBy"] = {"nodes": blocked, "totalCount": len(blocked)}
        with open(path, "w") as fh:
            json.dump(iss, fh)
    sys.stdout.write("")
elif args[:2] in (["issue", "comment"], ["issue", "close"]):
    if args[:2] == ["issue", "comment"] and "--body-file" in args:
        with open(os.path.join(state, "last-comment.md"), "w") as fh:
            fh.write(sys.stdin.read())
    sys.stdout.write("")
elif args[:2] == ["api", "graphql"]:
    number = None
    for arg in args:
        if arg.startswith("number="):
            number = int(arg.split("=", 1)[1])
    feature = json.loads(read("issue-%d.json" % number))
    def task_node(node):
        path = os.path.join(state, "issue-%d.json" % node["number"])
        if os.path.exists(path):
            with open(path) as fh:
                return json.load(fh)
        return node
    subs = []
    for node in (feature.get("subIssues") or {}).get("nodes", []):
        task = task_node(node)
        subs.append({
            "number": task.get("number", node["number"]),
            "title": task.get("title") or node.get("title"),
            "state": task.get("state") or node.get("state"),
            "labels": {"nodes": task.get("labels", [])},
            "blockedBy": task.get("blockedBy", {"nodes": []}),
        })
    payload = {"data": {"repository": {"issue": {
        "number": feature["number"],
        "title": feature["title"],
        "body": feature.get("body", ""),
        "state": feature["state"],
        "url": feature.get("url"),
        "labels": {"nodes": feature.get("labels", [])},
        "comments": {"nodes": feature.get("comments", [])},
        "subIssues": {"nodes": subs},
    }}}}
    sys.stdout.write(json.dumps(payload))
else:
    sys.stderr.write("fake gh: unexpected args %r\\n" % (args,))
    sys.exit(2)
'''

FAKE_REVDIFF = '''#!{python}
import json, os, sys

state = os.environ["FAKE_GH_STATE"]
args = sys.argv[1:]
with open(os.path.join(state, "revdiff.jsonl"), "a") as fh:
    fh.write(json.dumps(args) + "\\n")
source = sys.stdin.read()
with open(os.path.join(state, "reviewed-body.md"), "w") as fh:
    fh.write(source)
with open(os.path.join(state, "revdiff-env.json"), "w") as fh:
    json.dump({"REVDIFF_OUTPUT": os.environ.get("REVDIFF_OUTPUT")}, fh)
path = os.path.join(state, "revdiff-export.md")
if os.path.exists(path):
    with open(path) as fh:
        sys.stdout.write(fh.read())
exit_path = os.path.join(state, "revdiff-exit.txt")
if os.path.exists(exit_path):
    with open(exit_path) as fh:
        sys.exit(int(fh.read().strip()))
'''

FAKE_FZF = '''#!{python}
import json, os, shlex, sys

state = os.environ["FAKE_GH_STATE"]
args = sys.argv[1:]
rows = sys.stdin.read().splitlines()
sys.stderr.write("fzf draws its ui here\\n")
with open(os.path.join(state, "fzf.jsonl"), "a") as fh:
    fh.write(json.dumps(args) + "\\n")
header = args[args.index("--header") + 1]
name = header.replace(" ", "-")
with open(os.path.join(state, "rows-" + name + ".txt"), "w") as fh:
    fh.write("\\n".join(rows))
picks = {"sdlc features": "fzf-feature.txt", "sdlc actions": "fzf-action.txt"}
with open(os.path.join(state, picks[header])) as fh:
    want = fh.read().strip()
for row in rows:
    if row.split("\\t")[0] == want:
        sys.stdout.write(row + "\\n")
        sys.exit(0)
sys.exit(1)
'''

EXPORT = (
    "## issue-1.md:7 ( )\n"
    "Make this a link.\n"
    "\n"
    "## issue-1.md:13-15 ( )\n"
    "Split the plan.\n"
)

FILE_EXPORT = (
    "## issue-1.md (file-level)\n"
    "Body is long.\n"
    "\n"
    "## issue-1.md:13 ( )\n"
    " first\n"
    "second\n"
)


def label(name):
    return {"name": name}


def comment(author, body, at=COMMENT_AT):
    return {"author": {"login": author}, "body": body, "createdAt": at}


def nodes(items):
    return {"nodes": list(items), "totalCount": len(items)}


def sub(number, title, state="OPEN"):
    return {"number": number, "title": title, "state": state}


def issue(
    number,
    title,
    body="",
    labels=(),
    comments=(),
    state="OPEN",
    sub_issues=(),
    parent=None,
    blocked_by=(),
    url=None,
):
    return {
        "number": number,
        "title": title,
        "body": body,
        "state": state,
        "labels": [label(name) for name in labels],
        "comments": list(comments),
        "parent": nodes(parent or []),
        "subIssues": nodes(sub_issues),
        "blockedBy": nodes(blocked_by),
        "url": url or "https://github.com/test/repo/issues/%d" % number,
    }


def todo_feature(**overrides):
    fields = dict(
        number=1,
        title="Reduce bespoke tooling",
        body=DESIGN,
        labels=["type:feature", "repo:nix-config", "status:todo"],
    )
    fields.update(overrides)
    return issue(**fields)


def approved_feature(**overrides):
    fields = dict(
        number=1,
        title="Reduce bespoke tooling",
        body=DESIGN,
        labels=("type:feature", "repo:nix-config", "status:todo", "status:approved"),
        comments=(comment("sam", "Approved design sha256:%s" % DESIGN_SHA),),
        sub_issues=(sub(10, "T1: Build"), sub(11, "T2: Wire")),
    )
    fields.update(overrides)
    return issue(**fields)


class DesignHashTest(unittest.TestCase):
    def test_pinned_canonical_hash(self):
        self.assertEqual(sdlc_issues.design_hash(DESIGN), DESIGN_SHA)

    def test_ignores_crlf_trailing_space_and_blank_edges(self):
        noisy = DESIGN.replace("\n", "\r\n").replace(
            "1. One issue per feature.", "1. One issue per feature.   "
        )
        noisy = noisy.replace("## Plan", "\n\n## Plan") + "\r\n\r\n"
        self.assertEqual(sdlc_issues.design_hash(noisy), DESIGN_SHA)

    def test_annotation_lines_are_hashed_like_any_other_line(self):
        for indent in ("", "  "):
            with self.subTest(indent=indent):
                annotated = DESIGN.replace(
                    "Use GitHub issues.",
                    "%s> Sam: Is a label enough?\nUse GitHub issues." % indent,
                )
                self.assertNotEqual(sdlc_issues.design_hash(annotated), DESIGN_SHA)

    def test_stops_at_next_h2(self):
        changed_plan = DESIGN.replace("- [ ] T1: Build", "- [ ] T1: Different")
        self.assertEqual(sdlc_issues.design_hash(changed_plan), DESIGN_SHA)

    def test_missing_design_section(self):
        self.assertIsNone(sdlc_issues.design_hash("## Plan\n\n- [ ] T1: Build\n"))


class GhTest(unittest.TestCase):
    """Fake gh on PATH plus a temp registry; SDLC_REPO is test/repo."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = self.tmp.name
        self.state = os.path.join(self.root, "state")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.state)
        os.makedirs(self.bin)
        self.script("gh", FAKE_GH)

    def script(self, name, source):
        return write_script(self.bin, name, source)

    def serve(self, name, payload):
        with open(os.path.join(self.state, name), "w") as fh:
            fh.write(payload if isinstance(payload, str) else json.dumps(payload))

    def serve_list(self, issues):
        self.serve("list.json", issues)

    def serve_issue(self, iss):
        self.serve("issue-%d.json" % iss["number"], iss)

    def serve_feature(self, feature):
        self.serve_list([feature])
        self.serve_issue(feature)

    def serve_tasks(self):
        self.serve_issue(issue(10, "T1: Build", labels=["status:todo"]))
        self.serve_issue(issue(11, "T2: Wire", labels=["status:todo"]))

    def fakes(self):
        self.script("revdiff", FAKE_REVDIFF)
        self.script("fzf", FAKE_FZF)
        self.serve("fzf-feature.txt", "1\n")
        self.serve("fzf-action.txt", "show\n")

    def reset_calls(self):
        path = os.path.join(self.state, "calls.jsonl")
        if os.path.exists(path):
            os.unlink(path)

    def recorded(self, name):
        path = os.path.join(self.state, name)
        if not os.path.exists(path):
            return []
        with open(path) as fh:
            return [json.loads(line) for line in fh if line.strip()]

    def calls(self):
        return self.recorded("calls.jsonl")

    def calls_for(self, *prefix):
        return [call for call in self.calls() if call[: len(prefix)] == list(prefix)]

    def fzf_calls(self):
        return self.recorded("fzf.jsonl")

    def run_cli(self, *args, stdin=None, path=None):
        env = dict(os.environ)
        env["PATH"] = self.bin + os.pathsep + (path if path is not None else env.get("PATH", ""))
        env["SDLC_REPO"] = "test/repo"
        env["FAKE_GH_STATE"] = self.state
        return run_cli(args, env, stdin)


class ListTest(GhTest):
    def setUp(self):
        super().setUp()
        self.active = issue(
            1,
            "Reduce bespoke tooling",
            DESIGN,
            ["type:feature", "repo:nix-config", "status:todo"],
        )
        self.done = issue(
            2,
            "Old done thing",
            DESIGN,
            ["type:feature", "repo:sdlc", "status:done"],
            state="CLOSED",
        )
        self.canceled = issue(
            3,
            "Canceled thing",
            DESIGN,
            ["type:feature", "repo:other", "status:canceled"],
        )
        self.task = issue(4, "Task not a feature", "", ["status:todo"])
        self.serve_list([self.active, self.done, self.canceled, self.task])

    def test_default_excludes_terminal_and_non_features(self):
        out = self.run_cli("list")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#1", out.stdout)
        self.assertIn("Reduce bespoke tooling", out.stdout)
        self.assertIn("nix-config", out.stdout)
        self.assertIn("todo", out.stdout)
        for missing in ("#2", "#3", "#4"):
            self.assertNotIn(missing, out.stdout)

    def test_all_includes_closed_and_terminal(self):
        out = self.run_cli("list", "--all")
        self.assertEqual(out.returncode, 0, out.stderr)
        for present in ("#1", "#2", "#3"):
            self.assertIn(present, out.stdout)
        self.assertNotIn("#4", out.stdout)

    def test_path_format_is_tab_separated(self):
        out = self.run_cli("list", "--all", "--format", "path")
        self.assertEqual(out.returncode, 0, out.stderr)
        rows = [line.split("\t") for line in out.stdout.strip().splitlines()]
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0], ["1", "Reduce bespoke tooling", "todo", "nix-config"])
        self.assertEqual(rows[1][:3], ["2", "Old done thing", "done"])
        self.assertEqual(rows[1][3], "sdlc")
        self.assertEqual(rows[2][2], "canceled")

    def test_json_format_is_an_array(self):
        out = self.run_cli("list", "--format", "json")
        self.assertEqual(out.returncode, 0, out.stderr)
        rows = json.loads(out.stdout)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["number"], 1)
        self.assertEqual(rows[0]["title"], "Reduce bespoke tooling")
        self.assertEqual(rows[0]["status"], "todo")
        self.assertEqual(rows[0]["repo"], "nix-config")

    def test_human_format_appends_approval_suffixes(self):
        cases = (
            ((), "todo"),
            (("status:approved",), "todo+approved"),
            (("status:needs-reapproval",), "todo+needs-reapproval"),
            (("status:approved", "status:needs-reapproval"), "todo+needs-reapproval"),
        )
        for extra, expected in cases:
            with self.subTest(labels=extra):
                labels = ["type:feature", "repo:nix-config", "status:todo", *extra]
                self.serve_list([issue(9, "Feature", DESIGN, labels)])
                out = self.run_cli("list")
                self.assertEqual(out.returncode, 0, out.stderr)
                self.assertEqual(out.stdout.strip(), "#9 [%s] nix-config Feature" % expected)

    def test_every_gh_call_names_the_registry_repo(self):
        self.run_cli("list")
        for call in self.calls():
            self.assertIn("--repo", call)
            self.assertEqual(call[call.index("--repo") + 1], "test/repo")


class ShowTest(GhTest):
    def setUp(self):
        super().setUp()
        self.serve_feature(todo_feature(comments=[comment("sam", "Please clarify the rollout.")]))

    def test_show_prints_body_and_comment_thread(self):
        out = self.run_cli("show", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("Use GitHub issues.", out.stdout)
        self.assertIn("Please clarify the rollout.", out.stdout)
        self.assertIn("sam", out.stdout)

    def test_show_resolves_a_title_substring(self):
        out = self.run_cli("show", "bespoke")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("Use GitHub issues.", out.stdout)


class StatusTest(GhTest):
    def status(self, **feature_overrides):
        self.serve_feature(approved_feature(**feature_overrides))
        self.serve_tasks()
        out = self.run_cli("status", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout

    def test_approved_reports_hashes_author_and_counts(self):
        self.serve_feature(approved_feature())
        self.serve_issue(issue(10, "T1: Build", labels=["status:todo"]))
        self.serve_issue(
            issue(
                11,
                "T2: Wire",
                labels=["status:todo"],
                blocked_by=[sub(12, "T1 scaffold")],
            )
        )
        out = self.run_cli("status", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("design_sha256=%s" % DESIGN_SHA, out.stdout)
        self.assertIn("approved_sha256=%s" % DESIGN_SHA, out.stdout)
        self.assertIn("approved_by=sam", out.stdout)
        self.assertIn("approved_at=%s" % COMMENT_AT, out.stdout)
        self.assertIn("approval=approved", out.stdout)
        self.assertIn("open=2", out.stdout)
        self.assertIn("ready=1", out.stdout)
        self.assertIn("blocked=1", out.stdout)

    def test_stale_when_design_changed_after_approval(self):
        old = DESIGN.replace("Use GitHub issues.", "Use a different tracker.")
        out = self.status(
            comments=(comment("sam", "Approved design sha256:%s" % sdlc_issues.design_hash(old)),),
        )
        self.assertIn("approval=stale", out)
        self.assertIn("re-approval", out)

    def test_needs_reapproval_label_beats_approval(self):
        out = self.status(
            labels=(
                "type:feature",
                "repo:nix-config",
                "status:todo",
                "status:approved",
                "status:needs-reapproval",
            )
        )
        self.assertIn("approval=stale", out)

    def test_missing_without_approval(self):
        out = self.status(labels=("type:feature", "repo:nix-config", "status:todo"))
        self.assertIn("approval=missing", out)

    def test_status_uses_one_graphql_fetch(self):
        self.status()
        self.assertEqual(len(self.calls_for("api", "graphql")), 1)
        self.assertEqual(self.calls_for("issue", "view"), [])

    def test_approval_lines_that_are_not_the_whole_comment_do_not_count(self):
        for body in (
            "> Approved design sha256:%s" % DESIGN_SHA,
            "### Review\n\nApproved design sha256:%s\n\nLooks fine." % DESIGN_SHA,
        ):
            with self.subTest(body=body):
                out = self.status(
                    labels=("type:feature", "repo:nix-config", "status:todo"),
                    comments=(comment("sam", body),),
                )
                self.assertIn("approval=missing", out)


class NextTest(GhTest):
    def ready_fixture(self, **feature_overrides):
        self.serve_feature(approved_feature(**feature_overrides))
        self.serve_tasks()

    def test_next_uses_one_graphql_fetch(self):
        self.ready_fixture()
        out = self.run_cli("next", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(len(self.calls_for("api", "graphql")), 1)
        self.assertEqual(self.calls_for("issue", "view"), [])

    def test_next_prints_the_ready_task(self):
        self.ready_fixture()
        out = self.run_cli("next", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#10", out.stdout)
        self.assertIn("T1: Build", out.stdout)

    def test_next_without_feature_uses_first_active(self):
        self.ready_fixture()
        out = self.run_cli("next")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#10", out.stdout)

    def test_next_refuses_with_the_blocker(self):
        self.ready_fixture()
        self.serve_issue(
            issue(10, "T1: Build", labels=["status:todo"], blocked_by=[sub(7, "T0: Setup")])
        )
        self.serve_issue(issue(11, "T2: Wire", labels=["status:done"], state="CLOSED"))
        out = self.run_cli("next", "1")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("#7", out.stderr)
        self.assertIn("blocked by", out.stderr)

    def test_next_refuses_when_design_is_stale(self):
        old = DESIGN.replace("Use GitHub issues.", "Use a different tracker.")
        self.ready_fixture(
            comments=(comment("sam", "Approved design sha256:%s" % sdlc_issues.design_hash(old)),),
        )
        out = self.run_cli("next", "1")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("re-approval", out.stderr)

    def test_next_refuses_when_approval_is_missing(self):
        self.ready_fixture(labels=("type:feature", "repo:nix-config", "status:todo"))
        out = self.run_cli("next", "1")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("not approved", out.stderr)
        self.assertIn("approve", out.stderr)


class ApproveTest(GhTest):
    def setUp(self):
        super().setUp()
        self.feature = todo_feature()
        self.serve_feature(self.feature)

    def test_requires_a_tty_without_yes(self):
        out = self.run_cli("approve", "1")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("TTY", out.stderr + out.stdout)
        self.assertEqual(self.calls(), [])

    def test_adds_label_and_posts_hash_comment(self):
        out = self.run_cli("approve", "1", "--yes")
        self.assertEqual(out.returncode, 0, out.stderr)
        edits = self.calls_for("issue", "edit")
        self.assertEqual(len(edits), 1)
        edit = edits[0]
        self.assertEqual(edit[edit.index("--add-label") + 1], "status:approved")
        self.assertNotIn("status:todo", edit)
        comments = self.calls_for("issue", "comment")
        self.assertEqual(len(comments), 1)
        self.assertEqual(
            comments[0][comments[0].index("--body") + 1],
            "Approved design sha256:%s" % DESIGN_SHA,
        )
        self.assertIn("sha256:%s" % DESIGN_SHA, out.stdout)

    def test_refuses_non_feature(self):
        task = issue(10, "Task", DESIGN, ["status:todo"])
        self.serve_list([self.feature, task])
        self.serve_issue(task)
        out = self.run_cli("approve", "10", "--yes")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("type:feature", out.stderr + out.stdout)

    def test_removes_needs_reapproval_when_present(self):
        self.feature["labels"].append(label("status:needs-reapproval"))
        self.serve_issue(self.feature)
        out = self.run_cli("approve", "1", "--yes")
        self.assertEqual(out.returncode, 0, out.stderr)
        edit = self.calls_for("issue", "edit")[0]
        self.assertEqual(edit[edit.index("--remove-label") + 1], "status:needs-reapproval")


class NewTest(GhTest):
    def test_parses_printed_url_and_labels_the_code_repo(self):
        self.serve("create_url.txt", "https://github.com/test/repo/issues/7\n")
        out = self.run_cli("new", "my-feature", "--repo", "acme/widget")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#7", out.stdout)
        self.assertIn("https://github.com/test/repo/issues/7", out.stdout)
        create = self.calls_for("issue", "create")[0]
        self.assertEqual(create[create.index("--repo") + 1], "test/repo")
        for expected in ("type:feature", "repo:widget", "status:todo"):
            self.assertIn(expected, create)
        body = create[create.index("--body") + 1]
        self.assertIn("## Design", body)
        self.assertIn("## Plan", body)
        self.assertEqual(create[create.index("--title") + 1], "my feature")

    def test_title_override(self):
        self.serve("create_url.txt", "https://github.com/test/repo/issues/8\n")
        out = self.run_cli("new", "my-feature", "--repo", "acme/widget", "--title", "My Thing")
        self.assertEqual(out.returncode, 0, out.stderr)
        create = self.calls_for("issue", "create")[0]
        self.assertEqual(create[create.index("--title") + 1], "My Thing")


class TaskTest(GhTest):
    def setUp(self):
        super().setUp()
        body = DESIGN + "\n- [ ] T2: Wire (#12)\n"
        self.serve_feature(
            approved_feature(
                body=body,
                comments=[comment("sam", "Approved design sha256:%s" % sdlc_issues.design_hash(body))],
                sub_issues=(sub(10, "T1: Build"), sub(12, "T2: Wire")),
            )
        )
        self.serve("create_url.txt", "https://github.com/test/repo/issues/13\n")

    def test_task_add_sets_parent_and_translates_labels(self):
        out = self.run_cli("task", "add", "1", "T3: Test", "--needs", "T1,T2")
        self.assertEqual(out.returncode, 0, out.stderr)
        create = self.calls_for("issue", "create")[0]
        self.assertEqual(create[create.index("--parent") + 1], "1")
        blocked = [create[i + 1] for i, arg in enumerate(create) if arg == "--blocked-by"]
        self.assertEqual(blocked, ["10,12"])
        self.assertIn("status:todo", create)
        self.assertEqual(create[create.index("--title") + 1], "T3: Test")
        self.assertIn("#13", out.stdout)

    def test_task_add_accepts_issue_numbers(self):
        out = self.run_cli("task", "add", "1", "T4: More", "--needs", "10,#12")
        self.assertEqual(out.returncode, 0, out.stderr)
        create = self.calls_for("issue", "create")[0]
        blocked = [create[i + 1] for i, arg in enumerate(create) if arg == "--blocked-by"]
        self.assertEqual(blocked, ["10,12"])

    def test_task_add_rejects_unknown_label(self):
        out = self.run_cli("task", "add", "1", "T9: Nope", "--needs", "T8")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("T8", out.stderr)
        self.assertEqual(self.calls_for("issue", "create"), [])

    def test_task_start_swaps_the_lifecycle_label(self):
        self.serve_issue(issue(10, "T1: Build", labels=["status:todo"]))
        out = self.run_cli("task", "start", "10")
        self.assertEqual(out.returncode, 0, out.stderr)
        edit = self.calls_for("issue", "edit")[0]
        self.assertEqual(edit[edit.index("--add-label") + 1], "status:in-progress")
        self.assertIn("status:todo", edit)
        self.assertEqual(self.calls_for("issue", "close"), [])

    def test_task_done_closes_the_issue(self):
        self.serve_issue(issue(10, "T1: Build", labels=["status:in-progress"]))
        out = self.run_cli("task", "done", "10")
        self.assertEqual(out.returncode, 0, out.stderr)
        edit = self.calls_for("issue", "edit")[0]
        self.assertEqual(edit[edit.index("--add-label") + 1], "status:done")
        self.assertIn("status:in-progress", edit)
        self.assertEqual(len(self.calls_for("issue", "close")), 1)

    def test_task_cancel_closes_the_issue(self):
        self.serve_issue(issue(10, "T1: Build", labels=["status:todo"]))
        out = self.run_cli("task", "cancel", "10")
        self.assertEqual(out.returncode, 0, out.stderr)
        edit = self.calls_for("issue", "edit")[0]
        self.assertEqual(edit[edit.index("--add-label") + 1], "status:canceled")
        self.assertEqual(len(self.calls_for("issue", "close")), 1)

    def serve_dependency_case(self, blocked_by=(), blockers=()):
        self.serve_issue(
            issue(10, "T1: Build", labels=["status:todo"], blocked_by=list(blocked_by))
        )
        self.serve_issue(issue(12, "T2: Wire", labels=["status:todo"]))
        for number in blockers:
            self.serve_issue(issue(number, "T%d: Extra" % number, labels=["status:todo"]))

    def test_task_edit_sets_blocked_by_from_a_label(self):
        self.serve_dependency_case()
        out = self.run_cli("task", "edit", "10", "--needs", "T2")
        self.assertEqual(out.returncode, 0, out.stderr)
        edit = self.calls_for("issue", "edit")[0]
        self.assertEqual(
            [edit[i + 1] for i, arg in enumerate(edit) if arg == "--add-blocked-by"], ["12"]
        )
        self.assertNotIn("--remove-blocked-by", edit)
        self.assertIn("blocked_by=[12]", out.stdout)
        status = self.run_cli("status", "1")
        self.assertIn("#10 [blocked] T1: Build blocked_by=[12]", status.stdout)

    def test_task_edit_replaces_the_edges(self):
        self.serve_dependency_case(blocked_by=[sub(11, "T0: Prior"), sub(12, "T2: Wire")])
        out = self.run_cli("task", "edit", "10", "--needs", "12")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(
            self.calls_for("issue", "edit"),
            [["issue", "edit", "10", "--repo", "test/repo", "--remove-blocked-by", "11"]],
        )

    def test_task_edit_adds_one_edge_and_keeps_the_others(self):
        self.serve_dependency_case(blocked_by=[sub(12, "T2: Wire")], blockers=(14,))
        out = self.run_cli("task", "edit", "10", "--needs", "12,14")
        self.assertEqual(out.returncode, 0, out.stderr)
        edits = self.calls_for("issue", "edit")
        self.assertEqual(len(edits), 1)
        self.assertEqual(
            [edits[0][i + 1] for i, arg in enumerate(edits[0]) if arg == "--add-blocked-by"],
            ["14"],
        )
        self.assertNotIn("--remove-blocked-by", edits[0])

    def test_task_edit_refuses_a_cycle(self):
        # 10 is blocked by 12, so 12 cannot be blocked by 10.
        self.serve_dependency_case(blocked_by=[sub(12, "T2: Wire")])
        for token in ("10", "12"):
            with self.subTest(token=token):
                out = self.run_cli("task", "edit", "12", "--needs", token)
                self.assertEqual(out.returncode, 1)
                self.assertIn("cycle", out.stderr)
                self.assertEqual(self.calls_for("issue", "edit"), [])

    def test_task_edit_refuses_an_issue_that_is_not_a_task(self):
        self.serve_dependency_case()
        out = self.run_cli("task", "edit", "99", "--needs", "10")
        self.assertEqual(out.returncode, 1)
        self.assertIn("#99 is not a task", out.stderr)
        self.assertEqual(self.calls_for("issue", "edit"), [])

    def test_task_edit_needs_a_change(self):
        self.serve_dependency_case()
        out = self.run_cli("task", "edit", "10")
        self.assertEqual(out.returncode, 1)
        self.assertIn("--needs or --title", out.stderr)

    def test_task_edit_retitles_without_touching_the_edges(self):
        self.serve_dependency_case(blocked_by=[sub(12, "T2: Wire")])
        out = self.run_cli("task", "edit", "10", "--title", "T1: Build it")
        self.assertEqual(out.returncode, 0, out.stderr)
        edit = self.calls_for("issue", "edit")[0]
        self.assertEqual(edit[edit.index("--title") + 1], "T1: Build it")
        self.assertNotIn("--add-blocked-by", edit)
        self.assertNotIn("--remove-blocked-by", edit)
        status = self.run_cli("status", "1")
        self.assertIn("#10 [blocked] T1: Build it blocked_by=[12]", status.stdout)

    def test_next_reflects_a_new_edge(self):
        self.serve_dependency_case()
        first = self.run_cli("next", "1")
        self.assertIn("#10", first.stdout)
        out = self.run_cli("task", "edit", "10", "--needs", "12")
        self.assertEqual(out.returncode, 0, out.stderr)
        after = self.run_cli("next", "1")
        self.assertEqual(after.returncode, 0, after.stderr)
        self.assertIn("#12", after.stdout)

    def test_task_add_translates_a_suffixed_label(self):
        self.serve_feature(
            approved_feature(sub_issues=(sub(10, "T1: Build"), sub(15, "T2b: Prove")))
        )
        out = self.run_cli("task", "add", "1", "T3: Test", "--needs", "T2b")
        self.assertEqual(out.returncode, 0, out.stderr)
        create = self.calls_for("issue", "create")[0]
        self.assertEqual(
            [create[i + 1] for i, arg in enumerate(create) if arg == "--blocked-by"], ["15"]
        )


class FeatureTerminalTest(GhTest):
    def setUp(self):
        super().setUp()
        self.serve_feature(todo_feature())

    def test_complete_sets_done_and_closes(self):
        out = self.run_cli("complete", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        edit = self.calls_for("issue", "edit")[0]
        self.assertEqual(edit[edit.index("--add-label") + 1], "status:done")
        self.assertEqual(len(self.calls_for("issue", "close")), 1)

    def test_complete_refuses_open_tasks(self):
        self.serve_feature(todo_feature(sub_issues=(sub(10, "T1: Build"),)))
        self.serve_issue(issue(10, "T1: Build", labels=["status:todo"]))
        out = self.run_cli("complete", "1")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("open task", out.stderr + out.stdout)
        self.assertEqual(self.calls_for("issue", "close"), [])

    def test_cancel_sets_canceled_and_closes(self):
        out = self.run_cli("cancel", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        edit = self.calls_for("issue", "edit")[0]
        self.assertEqual(edit[edit.index("--add-label") + 1], "status:canceled")
        self.assertEqual(len(self.calls_for("issue", "close")), 1)


class RevdiffExportTest(unittest.TestCase):
    def test_parses_line_and_range_anchors(self):
        notes = sdlc_issues.parse_revdiff_annotations(EXPORT)
        self.assertEqual(notes[0].file, "issue-1.md")
        self.assertEqual((notes[0].start, notes[0].end), (7, None))
        self.assertEqual((notes[1].start, notes[1].end), (13, 15))
        self.assertEqual(notes[0].text, "Make this a link.")

    def test_parses_file_level_and_multiline_annotations(self):
        notes = sdlc_issues.parse_revdiff_annotations(FILE_EXPORT)
        self.assertEqual((notes[0].start, notes[0].end), (None, None))
        self.assertEqual(notes[0].text, "Body is long.")
        self.assertEqual(notes[1].text, "first\nsecond")

    def test_parses_diff_line_types(self):
        text = "## a.go:1 (-)\nremoved\n\n## a.go:2 (+)\nadded\n"
        notes = sdlc_issues.parse_revdiff_annotations(text)
        self.assertEqual([(note.start, note.text) for note in notes], [(1, "removed"), (2, "added")])

    def test_ignores_text_before_the_first_header(self):
        self.assertEqual(sdlc_issues.parse_revdiff_annotations("nothing here\n"), [])

    def test_preserves_blank_lines_inside_a_note(self):
        text = "## a.md:3 ( )\nfirst\n\nsecond paragraph\n"
        notes = sdlc_issues.parse_revdiff_annotations(text)
        self.assertEqual(notes[0].text, "first\n\nsecond paragraph")

    def test_unescapes_body_lines_that_look_like_headers(self):
        text = "## a.md:3 ( )\n ## not a record\n  ## pre-indented\n"
        notes = sdlc_issues.parse_revdiff_annotations(text)
        self.assertEqual(notes[0].text, "## not a record\n ## pre-indented")


class ReviewRenderTest(unittest.TestCase):
    def note(self, start=7, end=None, text="Make this a link."):
        return sdlc_issues.ReviewNote("issue-1.md", start, end, text)

    def test_quotes_the_anchored_body_lines(self):
        text = sdlc_issues.render_review(1, "Title", DESIGN, [self.note()])
        self.assertIn("## Review — #1 Title", text)
        self.assertIn("design sha256:%s" % DESIGN_SHA[:12], text)
        self.assertIn("### line 7", text)
        self.assertIn("> Use GitHub issues.", text)
        self.assertIn("<!-- sdlc-review:n1:", text)

    def test_quotes_ranges(self):
        text = sdlc_issues.render_review(
            1, "Title", DESIGN, [self.note(start=13, end=15, text="Split it.")]
        )
        self.assertIn("> ## Plan", text)
        self.assertIn("> - [ ] T1: Build", text)

    def test_skips_markers_already_posted(self):
        note = self.note()
        marker = sdlc_issues.review_marker(1, note, DESIGN.split("\n"))
        self.assertEqual(sdlc_issues.render_review(1, "Title", DESIGN, [note], {marker}), "")

    def test_marker_is_stable_for_the_same_anchor_and_text(self):
        self.assertEqual(
            sdlc_issues.review_marker(1, self.note()),
            sdlc_issues.review_marker(1, self.note()),
        )

    def test_marker_ignores_line_shift_but_tracks_content(self):
        body = "x\ny\nsame\nsame\n"
        lines = body.split("\n")
        first = sdlc_issues.ReviewNote("f", 3, None, "note")
        shifted = sdlc_issues.ReviewNote("f", 4, None, "note")
        self.assertEqual(
            sdlc_issues.review_marker(1, first, lines),
            sdlc_issues.review_marker(1, shifted, lines),
        )
        changed = "x\ny\nchanged\nsame\n"
        self.assertNotEqual(
            sdlc_issues.review_marker(1, first, lines),
            sdlc_issues.review_marker(1, first, changed.split("\n")),
        )


class ReviewCliTest(GhTest):
    def setUp(self):
        super().setUp()
        self.serve_issue(approved_feature())
        self.fakes()

    def export(self, text=EXPORT):
        self.serve("revdiff-export.md", text)

    def posted(self):
        with open(os.path.join(self.state, "last-comment.md")) as fh:
            return fh.read()

    def test_hands_the_body_to_revdiff_on_stdin(self):
        self.export()
        self.run_cli("review", "1")
        args = self.recorded("revdiff.jsonl")[0]
        self.assertIn("--stdin", args)
        self.assertIn("--no-tree", args)
        self.assertIn("--wrap", args)
        self.assertEqual(args[args.index("--stdin-name") + 1], "issue-1.md")
        with open(os.path.join(self.state, "reviewed-body.md")) as fh:
            self.assertEqual(fh.read(), DESIGN)

    def test_posts_one_aggregated_comment_with_quotes(self):
        self.export()
        out = self.run_cli("review", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        body = self.posted()
        self.assertIn("## Review — #1", body)
        self.assertIn("> Use GitHub issues.", body)
        self.assertIn("> ## Plan", body)
        self.assertIn("design sha256:%s" % DESIGN_SHA[:12], body)
        self.assertEqual(len(self.calls_for("issue", "comment")), 1)
        self.assertIn("tell the agent", out.stdout)

    def test_dry_run_prints_without_posting(self):
        self.export()
        out = self.run_cli("review", "1", "--dry-run")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("> Use GitHub issues.", out.stdout)
        self.assertEqual(self.calls_for("issue", "comment"), [])

    def test_no_comments_does_not_post(self):
        out = self.run_cli("review", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("no review notes", out.stdout)
        self.assertEqual(self.calls_for("issue", "comment"), [])

    def test_accepts_exit_code_10_for_annotations(self):
        self.export()
        self.serve("revdiff-exit.txt", "10")
        out = self.run_cli("review", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("> Use GitHub issues.", self.posted())

    def test_rejects_anchors_when_the_body_parsed_as_a_diff(self):
        self.export("## foo.go:1 (-)\nwhy?\n")
        out = self.run_cli("review", "1")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("parsed as a diff", out.stderr)
        self.assertEqual(self.calls_for("issue", "comment"), [])

    def test_ignores_revdiff_output_env(self):
        self.export()
        with mock.patch.dict(os.environ, {"REVDIFF_OUTPUT": "/tmp/revdiff-should-not-write"}):
            out = self.run_cli("review", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        with open(os.path.join(self.state, "revdiff-env.json")) as fh:
            self.assertIsNone(json.load(fh)["REVDIFF_OUTPUT"])

    def test_second_run_skips_markers_already_posted(self):
        self.export()
        self.run_cli("review", "1")
        posted = self.posted()
        self.serve_issue(approved_feature(comments=(comment("sam", posted),)))
        self.reset_calls()
        out = self.run_cli("review", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("no new review notes", out.stdout)
        self.assertEqual(self.calls_for("issue", "comment"), [])


class PickCliTest(GhTest):
    def setUp(self):
        super().setUp()
        self.serve_feature(todo_feature())
        self.fakes()

    def test_picks_the_feature_then_the_action(self):
        out = self.run_cli("pick")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("Use GitHub issues.", out.stdout)
        headers = [call[call.index("--header") + 1] for call in self.fzf_calls()]
        self.assertEqual(headers, ["sdlc features", "sdlc actions"])

    def test_feature_rows_carry_the_number_and_a_live_preview(self):
        self.run_cli("pick")
        args = self.fzf_calls()[0]
        self.assertEqual(args[args.index("--with-nth") + 1], "2..")
        self.assertEqual(args[args.index("--preview") + 1], "sdlc show {1}")
        with open(os.path.join(self.state, "rows-sdlc-features.txt")) as fh:
            self.assertEqual(
                fh.read().splitlines(),
                ["1\tReduce bespoke tooling [todo] nix-config"],
            )

    def test_all_reaches_terminal_features(self):
        self.serve_list(
            [
                todo_feature(),
                issue(
                    2,
                    "Old done thing",
                    DESIGN,
                    ["type:feature", "repo:sdlc", "status:done"],
                    state="CLOSED",
                ),
            ]
        )
        self.run_cli("pick", "--all")
        with open(os.path.join(self.state, "rows-sdlc-features.txt")) as fh:
            self.assertIn("2\tOld done thing [done] sdlc", fh.read())

    def test_canceling_the_feature_pick_runs_nothing(self):
        self.serve("fzf-feature.txt", "no-such-number\n")
        out = self.run_cli("pick")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(len(self.fzf_calls()), 1)
        self.assertEqual(self.calls_for("issue", "view"), [])

    def test_approve_from_the_picker_stays_behind_the_tty_gate(self):
        self.serve("fzf-action.txt", "approve\n")
        out = self.run_cli("pick")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("TTY", out.stderr + out.stdout)
        self.assertEqual(self.calls_for("issue", "edit"), [])

    def test_complete_from_the_picker_declines_by_default(self):
        self.serve("fzf-action.txt", "complete\n")
        out = self.run_cli("pick", stdin="n\n")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("not completed", out.stdout)
        self.assertEqual(self.calls_for("issue", "close"), [])

    def test_pick_keeps_the_fzf_ui_on_stderr(self):
        out = self.run_cli("pick")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("fzf draws its ui here", out.stderr)

    def test_bare_sdlc_prints_usage(self):
        out = self.run_cli()
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("usage: sdlc", out.stdout)


class CommentCliTest(GhTest):
    def setUp(self):
        super().setUp()
        self.serve_feature(todo_feature())
        self.fakes()

    def test_comment_opens_the_editor(self):
        out = self.run_cli("comment", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        call = self.calls_for("issue", "comment")[0]
        self.assertIn("--editor", call)

    def test_comment_requires_a_feature(self):
        out = self.run_cli("comment")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("required", out.stderr)


class CleanTest(unittest.TestCase):
    def test_clean_strips_control_characters_and_keeps_whitespace(self):
        self.assertEqual(sdlc_issues.clean("a\x1b[31mb\nc\t"), "a[31mb\nc\t")

    def test_one_line_removes_layout_characters(self):
        self.assertEqual(sdlc_issues.one_line("a\tb\nc\r"), "a b c ")

    def test_path_row_cleans_the_title(self):
        row = sdlc_issues.path_row(issue(1, "bad\x1b[31mtitle", labels=["repo:nix-config"]))
        self.assertNotIn("\x1b", row)


class EntryPointTest(unittest.TestCase):
    def test_the_console_script_target_is_an_importable_callable(self):
        with open(os.path.join(MODULE_DIR, "pyproject.toml"), "rb") as fh:
            scripts = tomllib.load(fh)["project"]["scripts"]
        module_name, _, attr = scripts["sdlc"].partition(":")
        entry = getattr(importlib.import_module(module_name), attr)
        self.assertTrue(callable(entry))


if __name__ == "__main__":
    unittest.main()
