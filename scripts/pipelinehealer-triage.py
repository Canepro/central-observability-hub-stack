#!/usr/bin/env python3
"""Classify low-context PipelineHealer GitHub issues.

The script is intentionally read-only. It parses an issue body from stdin, a
local file, or `gh issue view`, then emits a JSON classification that operators
can use before deciding whether a repo patch is warranted.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


def _read_issue_body(args: argparse.Namespace) -> str:
    if args.body_file:
        return Path(args.body_file).read_text(encoding="utf-8")
    if args.issue:
        proc = subprocess.run(
            ["gh", "issue", "view", str(args.issue), "--json", "body", "--jq", ".body"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return proc.stdout
    return sys.stdin.read()


def _extract_json_block(body: str, heading: str) -> dict[str, Any]:
    pattern = re.compile(
        rf"### {re.escape(heading)}\s*```json\s*(?P<json>\{{.*?\}})\s*```",
        flags=re.DOTALL,
    )
    match = pattern.search(body)
    if not match:
        return {}
    try:
        parsed = json.loads(match.group("json"))
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _extract_field(body: str, label: str) -> str:
    match = re.search(rf"\*\*{re.escape(label)}:\*\*\s*(.+)", body)
    return match.group(1).strip() if match else ""


def _extract_root_cause(body: str) -> str:
    match = re.search(r"### Root Cause\s*\n+(?P<value>.+?)(?:\n\n|###|\Z)", body, re.DOTALL)
    if not match:
        return ""
    return " ".join(line.strip() for line in match.group("value").splitlines() if line.strip())


def _workflow_run_marker(body: str) -> str:
    match = re.search(r"pipelinehealer:workflow-run:(\d+)", body)
    return match.group(1) if match else ""


def classify(body: str) -> dict[str, Any]:
    details = _extract_json_block(body, "Error Details")
    config_file = _extract_field(body, "Config File")
    root_cause = _extract_root_cause(body)
    workflow_run = _workflow_run_marker(body)
    lowered = body.lower()

    base: dict[str, Any] = {
        "classification": "unknown",
        "confidence": "low",
        "repo_side": "unknown",
        "root_cause": root_cause,
        "workflow_run_marker": workflow_run,
        "details": details,
        "operator_action": "Inspect the issue body, workflow run, and Jenkins job logs before patching.",
    }

    if config_file == "autofind.js" and "external api rate limit reached" in lowered:
        base.update(
            {
                "classification": "external_copilot_autofind_rate_limit",
                "confidence": "high",
                "repo_side": "no",
                "root_cause": "GitHub Copilot code review failed inside hosted autofind.js after a Copilot API 429.",
                "operator_action": (
                    "Validate the linked GitHub Actions run log for a hosted autofind.js 429, then wait for "
                    "the Copilot limit reset or change the Copilot model/quota setting. There is no "
                    "GrafanaLocal source file to patch for autofind.js."
                ),
            }
        )
        return base

    if details.get("source_selection_path") == "jenkins_bridge":
        evidence_quality = str(details.get("bridge_evidence_quality") or "")
        jenkins_url = str(details.get("jenkins_job_url") or "")
        if root_cause.startswith("Diagnosis failed: [Errno 2] No such file or directory"):
            base.update(
                {
                    "classification": "pipelinehealer_jenkins_bridge_diagnosis_runtime_error",
                    "confidence": "high" if evidence_quality == "log_excerpt" and jenkins_url else "medium",
                    "repo_side": "no_repo_patch_identified",
                    "root_cause": (
                        "PipelineHealer accepted Jenkins bridge evidence, then its diagnosis runtime raised "
                        "FileNotFoundError before producing a specific Jenkins failure diagnosis."
                    ),
                    "operator_action": (
                        "Treat duplicate low-confidence issues with this signature as PipelineHealer runtime "
                        "churn. Validate the Jenkins job URL and run scripts/test-pipelinehealer-bridge.sh; "
                        "patch GrafanaLocal only if the Jenkins console shows a repo-owned script or manifest "
                        "failure."
                    ),
                }
            )
            return base
        if evidence_quality == "summary_only":
            base.update(
                {
                    "classification": "jenkins_bridge_insufficient_evidence",
                    "confidence": "medium",
                    "repo_side": "investigate",
                    "operator_action": (
                        "Capture the Jenkins console tail or artifact output, rerun the bridge smoke test, "
                        "and resend only after the failing tool output is present."
                    ),
                }
            )
            return base

    return base


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--body-file", help="Path to a saved GitHub issue body")
    source.add_argument("--issue", type=int, help="GitHub issue number to fetch with gh")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON output")
    args = parser.parse_args()

    body = _read_issue_body(args)
    result = classify(body)
    json.dump(result, sys.stdout, indent=2 if args.pretty else None, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
