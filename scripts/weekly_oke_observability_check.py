#!/usr/bin/env python3
"""Read-only weekly OKE observability evidence collector.

The script is intentionally conservative. It gathers local repo state, Kubernetes
health, Argo CD app state, External Secrets readiness, version pins, and optional
GitHub queue metadata. It never decodes secret data or mutates live resources.
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
from typing import Any


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_GITHUB_REPO = "Canepro/central-observability-hub-stack"
WATCH_NAMESPACES = {
    "argocd",
    "external-secrets",
    "ingress-nginx",
    "kube-system",
    "monitoring",
}


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def run(cmd: list[str], timeout: int = 30, cwd: pathlib.Path = REPO_ROOT) -> dict[str, Any]:
    result: dict[str, Any] = {
        "command": cmd,
        "cwd": str(cwd),
        "ok": False,
        "returncode": None,
        "stdout": "",
        "stderr": "",
    }
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError:
        result["returncode"] = 127
        result["stderr"] = f"{cmd[0]} not found"
        return result
    except subprocess.TimeoutExpired as exc:
        result["returncode"] = 124
        result["stdout"] = exc.stdout or ""
        result["stderr"] = exc.stderr or f"timed out after {timeout}s"
        return result

    result["returncode"] = proc.returncode
    result["stdout"] = proc.stdout
    result["stderr"] = proc.stderr
    result["ok"] = proc.returncode == 0
    return result


def parse_json_command(cmd: list[str], timeout: int = 30) -> tuple[Any | None, dict[str, Any]]:
    result = run(cmd, timeout=timeout)
    if not result["ok"]:
        return None, result
    try:
        return json.loads(result["stdout"]), result
    except json.JSONDecodeError as exc:
        result["ok"] = False
        result["stderr"] = f"json parse failed: {exc}"
        return None, result


def kubectl_json(args: list[str], timeout: int = 30) -> tuple[Any | None, dict[str, Any]]:
    return parse_json_command(["kubectl", *args, "-o", "json"], timeout=timeout)


def get_condition_status(obj: dict[str, Any], condition_type: str) -> str:
    for condition in obj.get("status", {}).get("conditions", []) or []:
        if condition.get("type") == condition_type:
            status = condition.get("status", "Unknown")
            reason = condition.get("reason")
            return f"{status}/{reason}" if reason else status
    return "Missing"


def classify_app(app: dict[str, Any]) -> dict[str, Any]:
    metadata = app.get("metadata", {})
    spec = app.get("spec", {})
    status = app.get("status", {})
    name = metadata.get("name", "<unknown>")
    dest = spec.get("destination", {})
    dest_server = dest.get("server", "")
    health = status.get("health", {}).get("status", "Unknown")
    sync = status.get("sync", {}).get("status", "Unknown")
    is_aks = name.startswith("aks-") or "azmk8s.io" in dest_server
    expected = "aks-parked" if is_aks and sync == "Unknown" else "online"
    ok = (health == "Healthy" and sync == "Synced") or expected == "aks-parked"
    return {
        "name": name,
        "health": health,
        "sync": sync,
        "is_aks": is_aks,
        "namespace": dest.get("namespace"),
        "dest_server": dest_server,
        "expected": expected,
        "ok": ok,
    }


def collect_git() -> dict[str, Any]:
    branch = run(["git", "status", "--short", "--branch"])
    remote = run(["git", "remote", "-v"])
    head = run(["git", "rev-parse", "--short", "HEAD"])
    return {
        "status_short_branch": branch,
        "remote": remote,
        "head": head["stdout"].strip() if head["ok"] else None,
        "dirty_lines": [
            line
            for line in branch.get("stdout", "").splitlines()
            if line and not line.startswith("##")
        ],
    }


def collect_nodes() -> dict[str, Any]:
    data, raw = kubectl_json(["get", "nodes"], timeout=20)
    if data is None:
        return {"available": False, "raw": raw, "nodes": [], "ready": 0, "total": 0}

    nodes = []
    ready = 0
    for item in data.get("items", []):
        name = item.get("metadata", {}).get("name")
        ready_condition = get_condition_status(item, "Ready")
        if ready_condition.startswith("True"):
            ready += 1
        nodes.append(
            {
                "name": name,
                "ready": ready_condition,
                "version": item.get("status", {}).get("nodeInfo", {}).get("kubeletVersion"),
            }
        )
    return {"available": True, "raw": raw, "nodes": nodes, "ready": ready, "total": len(nodes)}


def collect_pods() -> dict[str, Any]:
    data, raw = kubectl_json(["get", "pods", "-A"], timeout=30)
    if data is None:
        return {"available": False, "raw": raw, "problem_pods": [], "watched_count": 0}

    problem_pods = []
    watched_count = 0
    restart_totals: list[dict[str, Any]] = []
    for item in data.get("items", []):
        metadata = item.get("metadata", {})
        namespace = metadata.get("namespace")
        if namespace not in WATCH_NAMESPACES:
            continue
        watched_count += 1
        name = metadata.get("name")
        status = item.get("status", {})
        phase = status.get("phase", "Unknown")
        container_statuses = status.get("containerStatuses", []) or []
        init_statuses = status.get("initContainerStatuses", []) or []
        not_ready = [
            c.get("name", "<unknown>")
            for c in container_statuses
            if phase == "Running" and not c.get("ready", False)
        ]
        waiting = []
        restart_count = 0
        for container in [*init_statuses, *container_statuses]:
            restart_count += int(container.get("restartCount", 0) or 0)
            state = container.get("state", {}) or {}
            if "waiting" in state:
                waiting.append(
                    {
                        "container": container.get("name"),
                        "reason": state["waiting"].get("reason"),
                    }
                )
        if restart_count:
            restart_totals.append(
                {
                    "namespace": namespace,
                    "pod": name,
                    "restarts": restart_count,
                }
            )
        if phase not in {"Running", "Succeeded"} or not_ready or waiting:
            problem_pods.append(
                {
                    "namespace": namespace,
                    "pod": name,
                    "phase": phase,
                    "not_ready": not_ready,
                    "waiting": waiting,
                    "restarts": restart_count,
                }
            )
    restart_totals.sort(key=lambda row: row["restarts"], reverse=True)
    return {
        "available": True,
        "raw": raw,
        "watched_count": watched_count,
        "problem_pods": problem_pods[:50],
        "restart_totals": restart_totals[:20],
    }


def collect_argocd_apps() -> dict[str, Any]:
    data, raw = kubectl_json(["get", "applications", "-n", "argocd"], timeout=30)
    if data is None:
        return {
            "available": False,
            "raw": raw,
            "apps": [],
            "problems": [],
            "aks_problems": [],
            "oke_problems": [],
            "aks_expected_parked": [],
        }

    apps = [classify_app(item) for item in data.get("items", [])]
    problems = [app for app in apps if not app["ok"]]
    aks_problems = [app for app in problems if app["is_aks"]]
    oke_problems = [app for app in problems if not app["is_aks"]]
    aks_expected = [app for app in apps if app["expected"] == "aks-parked"]
    counts: dict[str, int] = {}
    for app in apps:
        key = f"{app['health']}/{app['sync']}/{app['expected']}"
        counts[key] = counts.get(key, 0) + 1
    return {
        "available": True,
        "raw": raw,
        "apps": apps,
        "counts": counts,
        "problems": problems,
        "aks_problems": aks_problems,
        "oke_problems": oke_problems,
        "aks_expected_parked": aks_expected,
    }


def collect_pvcs() -> dict[str, Any]:
    data, raw = kubectl_json(["get", "pvc", "-n", "monitoring"], timeout=20)
    if data is None:
        return {"available": False, "raw": raw, "pvcs": [], "unbound": []}

    pvcs = []
    unbound = []
    for item in data.get("items", []):
        name = item.get("metadata", {}).get("name")
        phase = item.get("status", {}).get("phase")
        storage = item.get("spec", {}).get("resources", {}).get("requests", {}).get("storage")
        row = {"name": name, "phase": phase, "storage": storage}
        pvcs.append(row)
        if phase != "Bound":
            unbound.append(row)
    return {"available": True, "raw": raw, "pvcs": pvcs, "unbound": unbound}


def collect_external_secrets() -> dict[str, Any]:
    resources = {
        "externalsecrets": ["get", "externalsecrets.external-secrets.io", "-A"],
        "clustersecretstores": ["get", "clustersecretstores.external-secrets.io", "-A"],
    }
    output: dict[str, Any] = {}
    for key, args in resources.items():
        data, raw = kubectl_json(args, timeout=20)
        rows = []
        problems = []
        if data is not None:
            for item in data.get("items", []):
                metadata = item.get("metadata", {})
                ready = get_condition_status(item, "Ready")
                row = {
                    "namespace": metadata.get("namespace"),
                    "name": metadata.get("name"),
                    "ready": ready,
                }
                rows.append(row)
                if not ready.startswith("True"):
                    problems.append(row)
        output[key] = {
            "available": data is not None,
            "raw": raw,
            "items": rows,
            "problems": problems,
        }
    return output


def collect_resource_usage() -> dict[str, Any]:
    return {
        "nodes": run(["kubectl", "top", "nodes"], timeout=20),
        "monitoring_pods": run(
            ["kubectl", "top", "pods", "-n", "monitoring", "--sort-by=memory"],
            timeout=20,
        ),
    }


def collect_versions() -> dict[str, Any]:
    apps = []
    for path in sorted(glob.glob(str(REPO_ROOT / "argocd" / "applications" / "*.yaml"))):
        text = pathlib.Path(path).read_text(encoding="utf-8")
        name_match = re.search(r"metadata:\s*\n(?:[^\n]*\n)*?\s+name:\s*([^\n]+)", text)
        chart_match = re.search(r"\n\s+chart:\s*([^\n]+)", text)
        repo_matches = re.findall(r"\n\s+repoURL:\s*([^\n]+)", text)
        revisions = re.findall(r"\n\s+targetRevision:\s*([^\n]+)", text)
        target_revision = next((rev.strip() for rev in revisions if rev.strip() != "main"), None)
        apps.append(
            {
                "path": os.path.relpath(path, REPO_ROOT),
                "name": name_match.group(1).strip() if name_match else pathlib.Path(path).stem,
                "chart": chart_match.group(1).strip() if chart_match else None,
                "repo_url": repo_matches[0].strip() if repo_matches else None,
                "target_revision": target_revision,
            }
        )
    return {"applications": apps}


def collect_github(repo: str) -> dict[str, Any]:
    if not shutil.which("gh"):
        return {"available": False, "reason": "gh not found", "issues": [], "prs": []}

    issue_cmd = [
        "gh",
        "issue",
        "list",
        "--repo",
        repo,
        "--state",
        "open",
        "--limit",
        "50",
        "--json",
        "number,title,url,updatedAt,labels",
    ]
    pr_cmd = [
        "gh",
        "pr",
        "list",
        "--repo",
        repo,
        "--state",
        "open",
        "--limit",
        "50",
        "--json",
        "number,title,url,updatedAt,headRefName,baseRefName,isDraft,mergeStateStatus,reviewDecision",
    ]
    issues, issue_raw = parse_json_command(issue_cmd, timeout=30)
    prs, pr_raw = parse_json_command(pr_cmd, timeout=30)
    return {
        "available": bool(issue_raw["ok"] and pr_raw["ok"]),
        "issues": issues or [],
        "prs": prs or [],
        "raw": {"issues": issue_raw, "prs": pr_raw},
    }


def assess(report: dict[str, Any]) -> dict[str, Any]:
    findings = []
    status = "ok"

    nodes = report["checks"]["nodes"]
    if not nodes["available"]:
        findings.append({"severity": "warning", "message": "kubectl node check unavailable"})
        status = "partial"
    elif nodes["total"] == 0 or nodes["ready"] != nodes["total"]:
        findings.append(
            {
                "severity": "fail",
                "message": f"nodes Ready {nodes['ready']}/{nodes['total']}",
            }
        )
        status = "fail"

    pods = report["checks"]["pods"]
    if pods["available"] and pods["problem_pods"]:
        findings.append(
            {
                "severity": "fail",
                "message": f"{len(pods['problem_pods'])} watched pods are not cleanly Running/Succeeded",
            }
        )
        status = "fail"
    elif not pods["available"] and status == "ok":
        findings.append({"severity": "warning", "message": "kubectl pod check unavailable"})
        status = "partial"

    apps = report["checks"]["argocd_apps"]
    if apps["available"] and apps["oke_problems"]:
        findings.append(
            {
                "severity": "fail",
                "message": f"{len(apps['oke_problems'])} OKE Argo CD apps are not Healthy/Synced",
            }
        )
        status = "fail"
    if apps["available"] and apps["aks_problems"]:
        findings.append(
            {
                "severity": "warning",
                "message": f"{len(apps['aks_problems'])} AKS Argo CD apps are not Healthy/Synced; verify Azure expected state before escalating",
            }
        )
        if status == "ok":
            status = "partial"
    elif apps["available"] and apps["aks_expected_parked"]:
        findings.append(
            {
                "severity": "info",
                "message": f"{len(apps['aks_expected_parked'])} AKS apps are Unknown and classified as expected parked state",
            }
        )

    pvcs = report["checks"]["pvcs"]
    if pvcs["available"] and pvcs["unbound"]:
        findings.append({"severity": "fail", "message": "monitoring PVCs are not all Bound"})
        status = "fail"

    eso = report["checks"]["external_secrets"]
    for key, payload in eso.items():
        if payload["available"] and payload["problems"]:
            findings.append({"severity": "fail", "message": f"{key} has non-Ready items"})
            status = "fail"

    github = report["checks"]["github"]
    if github.get("available"):
        if github["issues"]:
            findings.append(
                {
                    "severity": "info",
                    "message": f"{len(github['issues'])} open GitHub issues need triage",
                }
            )
        if github["prs"]:
            findings.append(
                {
                    "severity": "info",
                    "message": f"{len(github['prs'])} open GitHub PRs need review",
                }
            )
    else:
        findings.append({"severity": "warning", "message": "GitHub CLI queue check unavailable"})
        if status == "ok":
            status = "partial"

    return {"status": status, "findings": findings}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=DEFAULT_GITHUB_REPO, help="GitHub repo in owner/name form")
    parser.add_argument("--output-dir", default=str(REPO_ROOT / "reports"), help="Evidence output directory")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero when assessment status is fail")
    args = parser.parse_args()

    output_dir = pathlib.Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    report: dict[str, Any] = {
        "generated_at": now_utc(),
        "repo_root": str(REPO_ROOT),
        "github_repo": args.repo,
        "policy": {
            "mode": "read-only",
            "secret_values": "not read, decoded, or printed",
            "live_mutation": "not performed",
            "aks": "classify as parked unless Azure control plane or user intent says it should be online",
        },
        "checks": {
            "git": collect_git(),
            "nodes": collect_nodes(),
            "pods": collect_pods(),
            "argocd_apps": collect_argocd_apps(),
            "pvcs": collect_pvcs(),
            "external_secrets": collect_external_secrets(),
            "resource_usage": collect_resource_usage(),
            "versions": collect_versions(),
            "github": collect_github(args.repo),
        },
    }
    report["assessment"] = assess(report)

    today = dt.datetime.now(dt.timezone.utc).date().isoformat()
    output_path = output_dir / f"{today}-weekly-oke-observability-check.json"
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")

    compact = {
        "generated_at": report["generated_at"],
        "status": report["assessment"]["status"],
        "evidence_path": str(output_path),
        "findings": report["assessment"]["findings"],
    }
    print(json.dumps(compact, indent=2))
    if args.strict and report["assessment"]["status"] == "fail":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
