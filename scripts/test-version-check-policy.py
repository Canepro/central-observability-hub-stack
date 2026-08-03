#!/usr/bin/env python3
"""Guard chart-source exclusions in the Jenkins version-check pipeline."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PIPELINE = ROOT / ".jenkins" / "version-check.Jenkinsfile"


def main() -> None:
    pipeline = PIPELINE.read_text(encoding="utf-8")

    assert "helm search repo grafana/loki" not in pipeline, (
        "grafana/loki is the Enterprise Logs chart and must not be queried "
        "as the OSS Loki update source"
    )

    component_line = next(
        line for line in pipeline.splitlines() if 'components="' in line
    )
    assert "LOKI" not in component_line.split('components="', 1)[1], (
        "Loki must remain outside automated manifest updates until the "
        "grafana-community source migration is reviewed"
    )

    assert "grafana-community/loki" in pipeline, (
        "Keep the chart-source migration rationale beside the exclusion"
    )

    print("version-check policy: ok")


if __name__ == "__main__":
    main()
