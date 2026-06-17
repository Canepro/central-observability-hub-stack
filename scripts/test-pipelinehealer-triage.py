#!/usr/bin/env python3
"""Regression tests for scripts/pipelinehealer-triage.py."""

from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "pipelinehealer-triage.py"
spec = importlib.util.spec_from_file_location("pipelinehealer_triage", SCRIPT)
assert spec and spec.loader
triage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(triage)


def test_autofind_rate_limit() -> None:
    body = """## Build Configuration Error

**Config File:** autofind.js
**Configuration Kind:** rate_limit

### Error
```
External API rate limit reached
```

<!-- pipelinehealer:workflow-run:26724719862 -->
"""
    result = triage.classify(body)
    assert result["classification"] == "external_copilot_autofind_rate_limit"
    assert result["repo_side"] == "no"
    assert result["workflow_run_marker"] == "26724719862"


def test_jenkins_bridge_file_not_found() -> None:
    body = """## CI/CD Failure Analysis

### Root Cause
Diagnosis failed: [Errno 2] No such file or directory

### Error Details
```json
{
  "source_selection_path": "jenkins_bridge",
  "bridge_evidence_quality": "log_excerpt",
  "bridge_run_result": "failure",
  "bridge_classification_state": "log_excerpt_available",
  "jenkins_job_url": "https://jenkins.canepro.me/job/GrafanaLocal/job/main/129/",
  "jenkins_delivery_id": "jenkins:GrafanaLocal/main#129"
}
```

<!-- pipelinehealer:workflow-run:129 -->
"""
    result = triage.classify(body)
    assert result["classification"] == "pipelinehealer_jenkins_bridge_diagnosis_runtime_error"
    assert result["repo_side"] == "no_repo_patch_identified"
    assert result["confidence"] == "high"


if __name__ == "__main__":
    test_autofind_rate_limit()
    test_jenkins_bridge_file_not_found()
    print("pipelinehealer triage tests passed")
