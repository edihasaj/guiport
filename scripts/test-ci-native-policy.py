#!/usr/bin/env python3
"""Exercise the hosted-macOS policy against parsed, checked-in workflows.

Ruby's bundled YAML parser supplies the parsing step, so this needs no Python
dependency. The small evaluator only covers the GitHub expression subset used
by these two guards.
"""

from __future__ import annotations

import re
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CI = ROOT / ".github/workflows/ci.yml"
RELEASE = ROOT / ".github/workflows/release.yml"


def fail(message: str) -> None:
    raise AssertionError(message)


def parse_workflow(workflow: str) -> dict[str, Any]:
    """Parse GitHub Actions YAML using the Ruby already available in CI/macOS."""
    ruby = """
      require 'json'
      require 'yaml'
      document = YAML.safe_load(STDIN.read, aliases: true)
      # YAML 1.1 parsers can deserialize the unquoted Actions key `on` as true.
      document['on'] = document.delete(true) if document.key?(true)
      puts JSON.generate(document)
    """
    result = subprocess.run(
        ["ruby", "-e", ruby],
        input=workflow,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        fail(f"workflow YAML did not parse: {result.stderr.strip()}")
    document = json.loads(result.stdout)
    if not isinstance(document, dict):
        fail("workflow YAML must be a mapping")
    return document


def triggers(workflow: dict[str, Any]) -> dict[str, Any]:
    value = workflow.get("on")
    if not isinstance(value, dict):
        fail("workflow must declare mapping-style triggers")
    return value


def job_condition(workflow: dict[str, Any], job: str) -> str:
    condition = workflow.get("jobs", {}).get(job, {}).get("if")
    if not isinstance(condition, str):
        fail(f"{job} must have an event guard")
    return condition


def github_value(path: str, event: dict[str, Any]) -> Any:
    value: Any = event
    keys = path.split(".")[1:]
    if path.startswith("github.event."):
        keys = keys[1:]
    elif path.startswith("inputs."):
        value = event.get("inputs", {})
    for key in keys:
        value = value.get(key) if isinstance(value, dict) else None
    return value


def evaluate(condition: str, event: dict[str, Any]) -> bool:
    """Evaluate the GitHub expression operators used by the checked-in guard."""
    def atom(match: re.Match[str]) -> str:
        path, operator, quoted = match.groups()
        return str(github_value(path, event) == quoted if operator == "==" else github_value(path, event) != quoted)

    expression = re.sub(
        r"\b((?:github|inputs)(?:\.[A-Za-z_]+)+)\s*(==|!=)\s*'([^']*)'",
        atom,
        condition,
    )
    expression = re.sub(
        r"\binputs\.run_native\b",
        str(bool(event.get("inputs", {}).get("run_native", False))),
        expression,
    )
    expression = expression.replace("&&", " and ").replace("||", " or ")
    tokens = re.findall(r"\(|\)|True|False|and|or|\s+", expression)
    if "".join(tokens) != expression:
        fail(f"unsupported or unexpanded GitHub expression: {expression!r}")
    return bool(eval(expression, {"__builtins__": {}}, {}))


def branch_matches(branches: Any, ref: str) -> bool:
    if not isinstance(branches, list):
        return False
    branch = ref.removeprefix("refs/heads/")
    return branch in branches


def workflow_is_triggered(workflow: dict[str, Any], event: dict[str, Any]) -> bool:
    configured = triggers(workflow)
    name = event["event_name"]
    if name not in configured:
        return False
    if name == "workflow_dispatch":
        return True
    if name == "push":
        config = configured[name]
        return isinstance(config, dict) and branch_matches(config.get("branches"), event.get("ref", ""))
    if name == "pull_request":
        config = configured[name]
        base = event.get("pull_request", {}).get("base", {}).get("ref", "")
        return isinstance(config, dict) and isinstance(config.get("branches"), list) and base in config["branches"]
    # schedule and the other no-filter triggers are considered configured.
    return True


def event(name: str, **values: Any) -> dict[str, Any]:
    return {"event_name": name, **values}


@dataclass(frozen=True)
class Case:
    name: str
    payload: dict[str, Any]
    expected: bool


def assert_ci_policy(workflow: dict[str, Any]) -> None:
    configured = triggers(workflow)
    for event_name in ("push", "pull_request", "workflow_dispatch"):
        if event_name not in configured:
            fail(f"CI is missing the {event_name} trigger")
    for event_name in ("push", "pull_request"):
        config = configured[event_name]
        if not isinstance(config, dict) or not {"main", "production"} <= set(config.get("branches", [])):
            fail(f"CI {event_name} must include main and production branches")
    dispatch = configured["workflow_dispatch"]
    run_native = dispatch.get("inputs", {}).get("run_native") if isinstance(dispatch, dict) else None
    if not isinstance(run_native, dict):
        fail("CI workflow_dispatch must declare the run_native input")
    if run_native.get("type") != "boolean" or run_native.get("default") is not False:
        fail("CI run_native must be a boolean input with default false")

    condition = job_condition(workflow, "build-test-macos")
    cases = (
        Case("main push", event("push", ref="refs/heads/main"), False),
        Case("master push", event("push", ref="refs/heads/master"), False),
        Case("feature push", event("push", ref="refs/heads/feature/policy"), False),
        Case("production push", event("push", ref="refs/heads/production"), True),
        Case("normal PR", event("pull_request", pull_request={"base": {"ref": "main"}}), False),
        Case("master PR", event("pull_request", pull_request={"base": {"ref": "master"}}), False),
        Case("dev PR", event("pull_request", pull_request={"base": {"ref": "dev"}}), False),
        Case("integration PR", event("pull_request", pull_request={"base": {"ref": "integration"}}), False),
        Case("production PR", event("pull_request", pull_request={"base": {"ref": "production"}}), True),
        Case("manual native false", event("workflow_dispatch", inputs={"run_native": False}), False),
        Case("manual native true", event("workflow_dispatch", inputs={"run_native": True}), True),
        Case("tag push", event("push", ref="refs/tags/v9.9.9"), False),
        Case("schedule", event("schedule"), False),
        Case("merge queue", event("merge_group"), False),
    )
    for case in cases:
        actual = workflow_is_triggered(workflow, case.payload) and evaluate(condition, case.payload)
        if actual != case.expected:
            fail(f"{case.name}: expected native={case.expected}, got {actual}")
        print(f"ok: {case.name}: native={actual}")


def assert_release_policy(workflow: dict[str, Any]) -> None:
    condition = job_condition(workflow, "bump")
    release_cases = (
        Case("manual release from main", event("workflow_dispatch", ref="refs/heads/main", actor="edi"), True),
        Case("manual release from feature", event("workflow_dispatch", ref="refs/heads/feature/policy", actor="edi"), False),
        Case("bot release", event("workflow_dispatch", ref="refs/heads/main", actor="github-actions[bot]"), False),
        # Protect this even if a later edit introduces a scheduled trigger.
        Case("scheduled release", event("schedule", ref="refs/heads/main", actor="edi"), False),
        Case("push release", event("push", ref="refs/heads/main", actor="edi"), False),
    )
    for case in release_cases:
        guard_allows = evaluate(condition, case.payload)
        if guard_allows != case.expected:
            fail(f"{case.name}: expected release guard={case.expected}, got {guard_allows}")
        actual = workflow_is_triggered(workflow, case.payload) and guard_allows
        if actual != case.expected:
            fail(f"{case.name}: expected release bump={case.expected}, got {actual}")
        print(f"ok: {case.name}: release bump={actual}")
    configured = triggers(workflow)
    if set(configured) != {"workflow_dispatch"}:
        fail("Release must be manual-only; do not publish from an automatic trigger")


def assert_mutation_rejected(name: str, workflow: str, policy: Any) -> None:
    try:
        policy(parse_workflow(workflow))
    except AssertionError:
        print(f"ok: mutation rejected: {name}")
        return
    fail(f"mutation unexpectedly passed: {name}")


def main() -> int:
    ci_source = CI.read_text()
    release_source = RELEASE.read_text()
    assert_ci_policy(parse_workflow(ci_source))
    assert_release_policy(parse_workflow(release_source))

    assert_mutation_rejected(
        "scheduled release trigger",
        release_source.replace(
            "  workflow_dispatch:\n",
            "  schedule:\n    - cron: '0 0 * * *'\n  workflow_dispatch:\n",
            1,
        ),
        assert_release_policy,
    )
    assert_mutation_rejected(
        "string run_native input",
        ci_source.replace("type: boolean", "type: string", 1),
        assert_ci_policy,
    )
    assert_mutation_rejected(
        "missing production PR filter",
        ci_source.replace("pull_request:\n    branches: [main, production]", "pull_request:\n    branches: [main]", 1),
        assert_ci_policy,
    )
    print("ok: parsed workflow triggers, dispatch schema, and guards enforce the native-runner policy")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
