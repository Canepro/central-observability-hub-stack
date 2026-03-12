#!/bin/sh
set -eu

OUTPUT_FILE="${1:?usage: capture-pipelinehealer-bridge-excerpt.sh <output-file>}"
CAPTURE_SHELL="${PH_CAPTURE_SHELL:-/bin/sh}"
STATUS_FILE="$(mktemp)"
SCRIPT_FILE="$(mktemp)"
trap 'rm -f "$STATUS_FILE" "$SCRIPT_FILE"' EXIT

mkdir -p "$(dirname "$OUTPUT_FILE")"
cat > "$SCRIPT_FILE"
chmod +x "$SCRIPT_FILE"

if [ ! -x "$CAPTURE_SHELL" ] && ! command -v "$CAPTURE_SHELL" >/dev/null 2>&1; then
  echo "PipelineHealer bridge capture: shell not found: $CAPTURE_SHELL" >&2
  exit 1
fi

(
  set +e
  "$CAPTURE_SHELL" "$SCRIPT_FILE" 2>&1
  echo $? > "$STATUS_FILE"
) | tee "$OUTPUT_FILE"

STATUS="$(cat "$STATUS_FILE" 2>/dev/null || echo 1)"
exit "$STATUS"
