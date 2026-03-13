#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_SCRIPT="${ROOT_DIR}/.jenkins/scripts/send-pipelinehealer-bridge.sh"

if [[ ! -x "${BRIDGE_SCRIPT}" ]]; then
  chmod +x "${BRIDGE_SCRIPT}"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

PORT_FILE="${WORK_DIR}/port"
REQUESTS_FILE="${WORK_DIR}/requests.jsonl"
SERVER_LOG="${WORK_DIR}/server.log"

python3 - <<'PY' "${PORT_FILE}" "${REQUESTS_FILE}" >"${SERVER_LOG}" 2>&1 &
import http.server
import json
import socketserver
import sys

port_file, requests_file = sys.argv[1], sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    counter = 0

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8")
        record = {
            "path": self.path,
            "headers": {k: v for k, v in self.headers.items()},
            "body": json.loads(body),
        }
        with open(requests_file, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record) + "\n")

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

        Handler.counter += 1
        if Handler.counter >= 2:
            raise SystemExit(0)

    def log_message(self, format, *args):
        return

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w", encoding="utf-8") as fh:
      fh.write(str(httpd.server_address[1]))
    try:
        httpd.serve_forever()
    except SystemExit:
        pass
PY
SERVER_PID=$!

for _ in $(seq 1 50); do
  [[ -s "${PORT_FILE}" ]] && break
  sleep 0.1
done

if [[ ! -s "${PORT_FILE}" ]]; then
  echo "bridge test server failed to start" >&2
  exit 1
fi

PORT="$(cat "${PORT_FILE}")"
BRIDGE_URL="http://127.0.0.1:${PORT}/bridge"
COMMON_ENV=(
  PH_BRIDGE_URL="${BRIDGE_URL}"
  PH_BRIDGE_SECRET="test-secret"
  PH_REPOSITORY="Canepro/central-observability-hub-stack"
  PH_JOB_NAME="GrafanaLocal/test-job"
  PH_JOB_URL="https://jenkins.canepro.me/job/GrafanaLocal/job/test-job/1/"
  PH_BUILD_NUMBER="1"
  PH_BRANCH="main"
  PH_COMMIT_SHA="0123456789abcdef0123456789abcdef01234567"
  PH_FAILURE_STAGE="terraform-validation"
  PH_FAILURE_SUMMARY="Terraform validation failed"
  PH_RESULT="FAILURE"
)

EXCERPT_FILE="${WORK_DIR}/excerpt.log"
cat >"${EXCERPT_FILE}" <<'EOF'
terraform init
Acquiring state lock. This may take a few moments...
Error: No valid credential sources found
EOF

env "${COMMON_ENV[@]}" PH_LOG_EXCERPT_FILE="${EXCERPT_FILE}" "${BRIDGE_SCRIPT}" >/dev/null

HTML_FILE="${WORK_DIR}/login.html"
cat >"${HTML_FILE}" <<'EOF'
<html><head><title>Login</title></head><body>
Authentication required
</body></html>
EOF

env "${COMMON_ENV[@]}" PH_LOG_EXCERPT_FILE="${HTML_FILE}" "${BRIDGE_SCRIPT}" >/dev/null

wait "${SERVER_PID}"

python3 - <<'PY' "${REQUESTS_FILE}"
import json
import sys

requests_path = sys.argv[1]
with open(requests_path, "r", encoding="utf-8") as fh:
    records = [json.loads(line) for line in fh if line.strip()]

assert len(records) == 2, f"expected 2 bridge requests, got {len(records)}"

first = records[0]["body"]
second = records[1]["body"]

assert first["failure"]["log_excerpt"], "expected first request to include a log excerpt"
assert "No valid credential sources found" in first["failure"]["log_excerpt"], "expected excerpt content in first request"
assert first["metadata"]["bridge_excerpt_present"] == "true", "expected excerpt flag true in first request"

assert second["failure"]["log_excerpt"] == "", "expected HTML auth page to be discarded"
assert second["metadata"]["bridge_excerpt_present"] == "false", "expected excerpt flag false in second request"

print("bridge smoke test passed")
PY
