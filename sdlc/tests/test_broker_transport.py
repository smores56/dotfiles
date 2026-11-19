"""Broker transport tests against a loopback fake proxy serving canned GitHub REST JSON."""

import http.server
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.parse
from unittest import mock

from support import COMMENT_AT, DESIGN, DESIGN_SHA, run_cli, write_script

import sdlc_issues

PREFIX = "/github-sdlc"
REPO_PATH = PREFIX + "/repos/test/repo"


class FakeBroker:
    """An HTTP path proxy: records requests, replays canned responses.

    A route registered once answers every matching request; a route registered
    twice answers in order, then repeats the last response.
    """

    def __init__(self):
        self.requests = []
        self.routes = {}
        broker = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _serve(self):
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                split = urllib.parse.urlsplit(self.path)
                body = None
                if raw:
                    try:
                        body = json.loads(raw)
                    except ValueError:
                        body = raw.decode("utf-8", "replace")
                broker.requests.append(
                    {
                        "method": self.command,
                        "path": split.path,
                        "query": urllib.parse.parse_qs(split.query),
                        "body": body,
                        "headers": {key.lower(): value for key, value in self.headers.items()},
                    }
                )
                status, payload = broker.respond(self.command, split.path)
                data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            do_GET = do_POST = do_DELETE = do_PATCH = _serve

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def respond(self, method, path):
        pending = self.routes.get((method, path))
        if not pending:
            return 404, {"message": "Not Found"}
        if len(pending) > 1:
            return pending.pop(0)
        return pending[0]

    def route(self, method, path, payload, status=200):
        self.routes.setdefault((method, path), []).append((status, payload))

    @property
    def url(self):
        # The trailing slash is deliberate: the client must normalize it.
        return "http://127.0.0.1:%d/" % self.server.server_address[1]

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


def rest_issue(number, title, body="", labels=(), state="open", db_id=None, **extra):
    payload = {
        "id": db_id or 1000 + number,
        "number": number,
        "title": title,
        "body": body,
        "state": state,
        "labels": [{"name": name} for name in labels],
        "html_url": extra.pop("html_url", "https://github.com/test/repo/issues/%d" % number),
    }
    payload.update(extra)
    return payload


def rest_comment(login, body, at=COMMENT_AT):
    return {"user": {"login": login}, "body": body, "created_at": at}


def graph_issue(feature, comments=(), tasks=()):
    return {
        "data": {
            "repository": {
                "issue": {
                    "number": feature["number"],
                    "title": feature["title"],
                    "body": feature["body"],
                    "state": "OPEN",
                    "url": feature["html_url"],
                    "labels": {"nodes": list(feature["labels"])},
                    "comments": {
                        "nodes": [
                            {
                                "author": {"login": (row.get("user") or {}).get("login")},
                                "body": row.get("body"),
                                "createdAt": row.get("created_at"),
                            }
                            for row in comments
                        ]
                    },
                    "subIssues": {"nodes": list(tasks)},
                }
            }
        }
    }


def graph_task(number, title, state="OPEN", labels=(), blocked_by=()):
    return {
        "number": number,
        "title": title,
        "state": state,
        "labels": {"nodes": [{"name": name} for name in labels]},
        "blockedBy": {"nodes": list(blocked_by)},
    }


class BrokerTest(unittest.TestCase):
    def setUp(self):
        self.broker = FakeBroker()
        self.addCleanup(self.broker.stop)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bin = os.path.join(self.tmp.name, "bin")
        os.makedirs(self.bin)

    def serve_feature(self, feature, comments=(), sub_issues=()):
        number = feature["number"]
        self.broker.route("GET", "%s/issues/%d" % (REPO_PATH, number), feature)
        self.broker.route("GET", "%s/issues/%d/comments" % (REPO_PATH, number), list(comments))
        self.broker.route("GET", "%s/issues/%d/sub_issues" % (REPO_PATH, number), list(sub_issues))

    def serve_blocked_by(self, number, blockers=()):
        self.broker.route(
            "GET", "%s/issues/%d/dependencies/blocked_by" % (REPO_PATH, number), list(blockers)
        )

    def requests(self, method=None, path=None):
        return [
            entry
            for entry in self.broker.requests
            if (method is None or entry["method"] == method)
            and (path is None or entry["path"] == path)
        ]

    def paths(self):
        return [entry["path"] for entry in self.broker.requests]

    def run_cli(self, *args, stdin=None, env=None):
        environ = dict(os.environ)
        environ["PATH"] = self.bin + os.pathsep + environ.get("PATH", "")
        environ["SDLC_REPO"] = "test/repo"
        environ["SDLC_TRANSPORT"] = "broker"
        environ["BROKER_URL"] = self.broker.url
        environ.pop("GITHUB_TOKEN", None)
        environ.pop("GH_TOKEN", None)
        environ.update(env or {})
        return run_cli(args, environ, stdin)


class TransportSelectionTest(BrokerTest):
    def test_gh_is_the_default_transport(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("SDLC_TRANSPORT", None)
            self.assertEqual(sdlc_issues.transport().name, "gh")

    def test_broker_transport_normalizes_the_base_url(self):
        for url in ("http://broker:8080", "http://broker:8080/"):
            with mock.patch.dict(os.environ, {"SDLC_TRANSPORT": "broker", "BROKER_URL": url}):
                transport = sdlc_issues.transport()
                self.assertEqual(transport.name, "broker")
                self.assertEqual(transport.base, "http://broker:8080/github-sdlc")

    def test_unknown_transport_fails_with_a_clear_error(self):
        out = self.run_cli("list", env={"SDLC_TRANSPORT": "carrier-pigeon"})
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("SDLC_TRANSPORT", out.stderr)
        self.assertIn("carrier-pigeon", out.stderr)
        self.assertIn("broker", out.stderr)
        self.assertNotIn("Traceback", out.stderr)

    def test_broker_without_a_url_fails_with_a_clear_error(self):
        out = self.run_cli("list", env={"BROKER_URL": ""})
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("BROKER_URL", out.stderr)
        self.assertNotIn("Traceback", out.stderr)


class ListTest(BrokerTest):
    def setUp(self):
        super().setUp()
        self.feature = rest_issue(
            1,
            "Reduce bespoke tooling",
            DESIGN,
            ["type:feature", "repo:nix-config", "status:todo"],
        )
        self.task = rest_issue(10, "T1: Build", labels=["status:todo"])
        self.other = rest_issue(4, "Just a note", labels=["status:todo"])
        self.broker.route("GET", REPO_PATH + "/issues", [self.feature, self.task, self.other])
        self.broker.route(
            "GET",
            REPO_PATH + "/issues/1/comments",
            [rest_comment("sam", "Approved design sha256:%s" % DESIGN_SHA)],
        )
        self.broker.route("GET", REPO_PATH + "/issues/1/sub_issues", [self.task])
        self.serve_blocked_by(10)

    def test_list_reads_rest_under_the_broker_base_path(self):
        out = self.run_cli("list")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(
            out.stdout.strip(), "#1 [todo] nix-config Reduce bespoke tooling"
        )
        self.assertTrue(all(path.startswith(PREFIX + "/") for path in self.paths()), self.paths())
        listing = self.requests("GET", REPO_PATH + "/issues")[0]
        self.assertEqual(listing["query"]["state"], ["open"])
        self.assertEqual(listing["query"]["per_page"], ["100"])
        self.assertEqual(listing["query"]["page"], ["1"])

    def test_list_sends_no_authorization_header(self):
        out = self.run_cli("list", env={"GITHUB_TOKEN": "secret-should-not-leak"})
        self.assertEqual(out.returncode, 0, out.stderr)
        for entry in self.broker.requests:
            self.assertNotIn("authorization", entry["headers"])
            self.assertNotIn("secret-should-not-leak", json.dumps(entry["headers"]))

    def test_list_hydrates_comments_and_sub_issues_for_features_only(self):
        self.run_cli("list")
        self.assertEqual(len(self.requests("GET", REPO_PATH + "/issues/1/comments")), 1)
        self.assertEqual(len(self.requests("GET", REPO_PATH + "/issues/1/sub_issues")), 1)
        self.assertEqual(self.requests("GET", REPO_PATH + "/issues/4/comments"), [])

    def test_broker_needs_no_gh_on_path(self):
        # PATH holds only the empty temp bin dir: any gh shell-out would fail.
        out = self.run_cli("list", env={"PATH": self.bin})
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#1", out.stdout)

    def test_list_paginates_until_the_limit(self):
        page_one = [rest_issue(100 + n, "Note %d" % n) for n in range(100)]
        self.broker.routes[("GET", REPO_PATH + "/issues")] = [
            (200, page_one),
            (200, [rest_issue(900, "Last note")]),
        ]
        out = self.run_cli("list")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.strip(), "")
        pages = [entry["query"]["page"] for entry in self.requests("GET", REPO_PATH + "/issues")]
        self.assertEqual(pages, [["1"], ["2"]])

    def test_list_json_reports_the_approval_from_rest_comments(self):
        self.feature["labels"].append({"name": "status:approved"})
        out = self.run_cli("list", "--format", "json")
        self.assertEqual(out.returncode, 0, out.stderr)
        rows = json.loads(out.stdout)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["number"], 1)
        self.assertEqual(rows[0]["approval"], "approved")

    def test_list_all_asks_for_every_state(self):
        closed = rest_issue(2, "Old", DESIGN, ["type:feature"], state="closed")
        self.broker.routes[("GET", REPO_PATH + "/issues")] = [(200, [closed])]
        self.broker.route("GET", REPO_PATH + "/issues/2/comments", [])
        self.broker.route("GET", REPO_PATH + "/issues/2/sub_issues", [])
        out = self.run_cli("list", "--all")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#2", out.stdout)
        listing = self.requests("GET", REPO_PATH + "/issues")[0]
        self.assertEqual(listing["query"]["state"], ["all"])


class StatusTest(BrokerTest):
    def setUp(self):
        super().setUp()
        self.feature = rest_issue(
            1,
            "Reduce bespoke tooling",
            DESIGN,
            ["type:feature", "repo:nix-config", "status:todo", "status:approved"],
        )
        self.broker.route("GET", REPO_PATH + "/issues", [self.feature])
        self.broker.route(
            "POST",
            PREFIX + "/graphql",
            graph_issue(
                self.feature,
                comments=[rest_comment("sam", "Approved design sha256:%s" % DESIGN_SHA)],
                tasks=[
                    graph_task(10, "T1: Build", labels=["status:todo"]),
                    graph_task(11, "T2: Wire", labels=["status:todo"], blocked_by=[
                        {"number": 10, "title": "T1: Build", "state": "OPEN"}
                    ]),
                ],
            ),
        )

    def test_status_posts_the_feature_graph_query(self):
        out = self.run_cli("status", "1")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("approval=approved", out.stdout)
        self.assertIn("tasks: open=2 ready=1 blocked=1", out.stdout)
        posted = self.requests("POST", PREFIX + "/graphql")
        self.assertEqual(len(posted), 1)
        self.assertEqual(posted[0]["body"]["query"], sdlc_issues.FEATURE_GRAPH_QUERY)
        self.assertEqual(
            posted[0]["body"]["variables"], {"owner": "test", "name": "repo", "number": 1}
        )


class ApproveTest(BrokerTest):
    def setUp(self):
        super().setUp()
        self.feature = rest_issue(
            1,
            "Reduce bespoke tooling",
            DESIGN,
            ["type:feature", "repo:nix-config", "status:todo"],
        )
        self.serve_feature(self.feature)
        self.broker.route("POST", REPO_PATH + "/issues/1/labels", [{"name": "status:approved"}])
        self.broker.route(
            "POST",
            REPO_PATH + "/issues/1/comments",
            rest_comment("sdlc-broker", "Approved design sha256:%s" % DESIGN_SHA),
            status=201,
        )

    def test_approve_adds_the_label_and_posts_the_hash_comment(self):
        out = self.run_cli("approve", "1", "--yes")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("approved #1 sha256:%s" % DESIGN_SHA, out.stdout)
        labels = self.requests("POST", REPO_PATH + "/issues/1/labels")
        self.assertEqual(len(labels), 1)
        self.assertEqual(labels[0]["body"], {"labels": ["status:approved"]})
        comments = self.requests("POST", REPO_PATH + "/issues/1/comments")
        self.assertEqual(len(comments), 1)
        self.assertEqual(comments[0]["body"], {"body": "Approved design sha256:%s" % DESIGN_SHA})
        self.assertEqual(self.requests("DELETE"), [])

    def test_approve_removes_needs_reapproval_when_present(self):
        self.feature["labels"].append({"name": "status:needs-reapproval"})
        self.broker.routes[("GET", REPO_PATH + "/issues/1")] = [(200, self.feature)]
        self.broker.route("DELETE", REPO_PATH + "/issues/1/labels/status%3Aneeds-reapproval", [])
        out = self.run_cli("approve", "1", "--yes")
        self.assertEqual(out.returncode, 0, out.stderr)
        removed = self.requests("DELETE")
        self.assertEqual(
            [urllib.parse.unquote(entry["path"]) for entry in removed],
            [REPO_PATH + "/issues/1/labels/status:needs-reapproval"],
        )

    def test_approve_still_refuses_a_non_feature(self):
        task = rest_issue(10, "Task", DESIGN, ["status:todo"])
        self.broker.routes[("GET", REPO_PATH + "/issues/1")] = [(200, task)]
        out = self.run_cli("approve", "1", "--yes")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("type:feature", out.stderr)
        self.assertEqual(self.requests("POST"), [])


class NewTest(BrokerTest):
    def test_new_creates_the_feature_over_http(self):
        self.broker.route(
            "POST",
            REPO_PATH + "/issues",
            rest_issue(7, "my feature", "## Design\n", ["type:feature"], db_id=770),
            status=201,
        )
        out = self.run_cli("new", "my-feature", "--repo", "acme/widget")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#7", out.stdout)
        self.assertIn("https://github.com/test/repo/issues/7", out.stdout)
        create = self.requests("POST", REPO_PATH + "/issues")
        self.assertEqual(len(create), 1)
        body = create[0]["body"]
        self.assertEqual(body["title"], "my feature")
        self.assertEqual(body["labels"], ["type:feature", "repo:widget", "status:todo"])
        self.assertIn("## Design", body["body"])
        self.assertIn("## Plan", body["body"])


class TaskTest(BrokerTest):
    def setUp(self):
        super().setUp()
        body = DESIGN + "\n- [ ] T2: Wire (#12)\n"
        self.feature = rest_issue(
            1,
            "Reduce bespoke tooling",
            body,
            ["type:feature", "repo:nix-config", "status:todo", "status:approved"],
        )
        self.serve_feature(
            self.feature,
            comments=[rest_comment("sam", "Approved design sha256:%s" % sdlc_issues.design_hash(body))],
            sub_issues=[rest_issue(10, "T1: Build"), rest_issue(12, "T2: Wire")],
        )
        self.serve_blocked_by(10)
        self.serve_blocked_by(12)
        self.broker.route("GET", REPO_PATH + "/issues/10", rest_issue(10, "T1: Build", db_id=1010))
        self.broker.route("GET", REPO_PATH + "/issues/12", rest_issue(12, "T2: Wire", db_id=1012))
        self.broker.route(
            "POST",
            REPO_PATH + "/issues",
            rest_issue(13, "T3: Test", db_id=991),
            status=201,
        )
        self.broker.route("POST", REPO_PATH + "/issues/1/sub_issues", rest_issue(13, "T3: Test"))
        self.broker.route("POST", REPO_PATH + "/issues/13/dependencies/blocked_by", rest_issue(10, "T1"))

    def test_task_add_names_the_parent_and_the_blockers(self):
        out = self.run_cli("task", "add", "1", "T3: Test", "--needs", "T1,T2")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#13", out.stdout)
        create = self.requests("POST", REPO_PATH + "/issues")[0]["body"]
        self.assertEqual(create["title"], "T3: Test")
        self.assertEqual(create["body"], "Part of #1.")
        self.assertEqual(create["labels"], ["status:todo"])
        parent = self.requests("POST", REPO_PATH + "/issues/1/sub_issues")
        self.assertEqual([entry["body"] for entry in parent], [{"sub_issue_id": 991}])
        blocked = self.requests("POST", REPO_PATH + "/issues/13/dependencies/blocked_by")
        self.assertEqual(
            [entry["body"] for entry in blocked], [{"issue_id": 1010}, {"issue_id": 1012}]
        )

    def test_task_add_accepts_issue_numbers(self):
        out = self.run_cli("task", "add", "1", "T4: More", "--needs", "10,#12")
        self.assertEqual(out.returncode, 0, out.stderr)
        blocked = self.requests("POST", REPO_PATH + "/issues/13/dependencies/blocked_by")
        self.assertEqual(
            [entry["body"] for entry in blocked], [{"issue_id": 1010}, {"issue_id": 1012}]
        )

    def test_task_done_swaps_the_label_and_closes(self):
        self.broker.routes[("GET", REPO_PATH + "/issues/10")] = [
            (200, rest_issue(10, "T1: Build", labels=["status:in-progress"]))
        ]
        self.broker.route("POST", REPO_PATH + "/issues/10/labels", [{"name": "status:done"}])
        self.broker.route("DELETE", REPO_PATH + "/issues/10/labels/status%3Ain-progress", [])
        self.broker.route("PATCH", REPO_PATH + "/issues/10", rest_issue(10, "T1: Build", state="closed"))
        out = self.run_cli("task", "done", "10")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("#10 status:done", out.stdout)
        added = self.requests("POST", REPO_PATH + "/issues/10/labels")
        self.assertEqual([entry["body"] for entry in added], [{"labels": ["status:done"]}])
        self.assertEqual(
            [urllib.parse.unquote(entry["path"]) for entry in self.requests("DELETE")],
            [REPO_PATH + "/issues/10/labels/status:in-progress"],
        )
        patched = self.requests("PATCH", REPO_PATH + "/issues/10")
        self.assertEqual([entry["body"] for entry in patched], [{"state": "closed"}])

    def test_task_start_does_not_close(self):
        self.broker.routes[("GET", REPO_PATH + "/issues/10")] = [
            (200, rest_issue(10, "T1: Build", labels=["status:todo"]))
        ]
        self.broker.route("POST", REPO_PATH + "/issues/10/labels", [{"name": "status:in-progress"}])
        self.broker.route("DELETE", REPO_PATH + "/issues/10/labels/status%3Atodo", [])
        out = self.run_cli("task", "start", "10")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(self.requests("PATCH"), [])


class CommentTest(BrokerTest):
    def setUp(self):
        super().setUp()
        self.feature = rest_issue(1, "Reduce bespoke tooling", DESIGN, ["type:feature"])
        self.serve_feature(self.feature)

    def test_comment_opens_the_editor_and_posts_over_http(self):
        editor = write_script(
            self.bin,
            "fake-editor",
            "#!%s\nimport sys\nopen(sys.argv[1], 'w').write('A note from the editor\\n')\n"
            % sys.executable,
        )
        self.broker.route(
            "POST", REPO_PATH + "/issues/1/comments", rest_comment("sam", "x"), status=201
        )
        out = self.run_cli("comment", "1", env={"EDITOR": editor, "VISUAL": "", "GIT_EDITOR": ""})
        self.assertEqual(out.returncode, 0, out.stderr)
        posted = self.requests("POST", REPO_PATH + "/issues/1/comments")
        self.assertEqual([entry["body"] for entry in posted], [{"body": "A note from the editor"}])


class ErrorTest(BrokerTest):
    def test_non_2xx_maps_to_the_cli_error_path(self):
        self.broker.route("GET", REPO_PATH + "/issues", {"message": "boom"}, status=500)
        out = self.run_cli("list")
        self.assertEqual(out.returncode, 1)
        self.assertIn("failed:", out.stderr)
        self.assertIn("boom", out.stderr)
        self.assertNotIn("Traceback", out.stderr)
        self.assertEqual(out.stdout, "")

    def test_missing_route_reports_not_found(self):
        out = self.run_cli("list")
        self.assertEqual(out.returncode, 1)
        self.assertIn("Not Found", out.stderr)

    def test_unreachable_broker_maps_to_the_cli_error_path(self):
        out = self.run_cli("list", env={"BROKER_URL": "http://127.0.0.1:9/"})
        self.assertEqual(out.returncode, 1)
        self.assertIn("failed:", out.stderr)
        self.assertNotIn("Traceback", out.stderr)


HOOK_PATH = "/github-hooks/repos/test/repo/hooks"
CAPABILITY_URL = "https://agent-hooks.sammohr.dev/hook/cap-abc123"


class HookTest(BrokerTest):
    def serve_hook(self, hook_id=42, status=201):
        self.broker.route(
            "POST",
            HOOK_PATH,
            {"id": hook_id, "config": {"url": CAPABILITY_URL}},
            status=status,
        )

    def secret_file(self, secret="s3cr3t-value\n"):
        path = os.path.join(self.tmp.name, "hook.secret")
        with open(path, "w") as fh:
            fh.write(secret)
        return path

    def test_hook_add_posts_the_webhook_to_the_github_hooks_host(self):
        self.serve_hook()
        out = self.run_cli("hook", "add", "test/repo", "--url", CAPABILITY_URL)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(self.paths(), [HOOK_PATH])
        posted = self.requests("POST", HOOK_PATH)[0]
        self.assertEqual(posted["body"]["name"], "webhook")
        self.assertIs(posted["body"]["active"], True)
        self.assertEqual(
            posted["body"]["events"],
            ["push", "pull_request", "issues", "issue_comment"],
        )
        config = posted["body"]["config"]
        self.assertEqual(config["url"], CAPABILITY_URL)
        self.assertEqual(config["content_type"], "json")
        self.assertEqual(config["insecure_ssl"], "0")
        self.assertNotIn("secret", config)
        self.assertNotIn("authorization", posted["headers"])
        self.assertIn("42", out.stdout)
        self.assertIn(CAPABILITY_URL, out.stdout)

    def test_hook_add_takes_a_comma_separated_event_list(self):
        self.serve_hook()
        out = self.run_cli(
            "hook", "add", "test/repo", "--url", CAPABILITY_URL,
            "--events", "issues, issue_comment,issues, ",
        )
        self.assertEqual(out.returncode, 0, out.stderr)
        posted = self.requests("POST", HOOK_PATH)[0]
        self.assertEqual(posted["body"]["events"], ["issues", "issue_comment"])

    def test_hook_add_embeds_the_secret_and_never_prints_it(self):
        self.serve_hook()
        path = self.secret_file()
        out = self.run_cli(
            "hook", "add", "test/repo", "--url", CAPABILITY_URL, "--secret-file", path,
        )
        self.assertEqual(out.returncode, 0, out.stderr)
        posted = self.requests("POST", HOOK_PATH)[0]
        self.assertEqual(posted["body"]["config"]["secret"], "s3cr3t-value")
        self.assertNotIn("s3cr3t-value", out.stdout)
        self.assertNotIn("s3cr3t-value", out.stderr)

    def test_hook_add_rejects_a_url_outside_the_agent_receiver_before_http(self):
        for url in (
            "https://evil.example/hook/cap",
            "https://agent-hooks.sammohr.dev.evil.example/hook/cap",
            "http://agent-hooks.sammohr.dev/hook/cap",
            "https://agent-hooks.sammohr.dev/",
        ):
            with self.subTest(url=url):
                out = self.run_cli("hook", "add", "test/repo", "--url", url)
                self.assertEqual(out.returncode, 1)
                self.assertIn("agent-hooks.sammohr.dev", out.stderr)
                self.assertNotIn("Traceback", out.stderr)
        self.assertEqual(self.broker.requests, [])

    def test_hook_add_reports_a_broker_403_with_its_message(self):
        self.broker.route(
            "POST", HOOK_PATH, {"message": "hooks are not permitted here"}, status=403
        )
        out = self.run_cli("hook", "add", "test/repo", "--url", CAPABILITY_URL)
        self.assertEqual(out.returncode, 1)
        self.assertIn("403", out.stderr)
        self.assertIn("hooks are not permitted here", out.stderr)
        self.assertNotIn("Traceback", out.stderr)
        self.assertEqual(out.stdout, "")

    def test_hook_add_fails_before_http_when_the_secret_file_is_missing(self):
        out = self.run_cli(
            "hook", "add", "test/repo", "--url", CAPABILITY_URL,
            "--secret-file", os.path.join(self.tmp.name, "absent"),
        )
        self.assertEqual(out.returncode, 1)
        self.assertIn("--secret-file", out.stderr)
        self.assertEqual(self.broker.requests, [])

    def test_hook_add_needs_an_owner_name_repo(self):
        out = self.run_cli("hook", "add", "test", "--url", CAPABILITY_URL)
        self.assertEqual(out.returncode, 1)
        self.assertIn("owner/name", out.stderr)
        self.assertEqual(self.broker.requests, [])


if __name__ == "__main__":
    unittest.main()
