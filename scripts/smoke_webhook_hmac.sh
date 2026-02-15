#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

API_PORT="${ORCHIVISTE_WEBHOOK_TEST_API_PORT:-29780}"
ANALYSE_PORT="${ORCHIVISTE_WEBHOOK_TEST_ANALYSE_PORT:-29781}"
WEBHOOK_PORT="${ORCHIVISTE_WEBHOOK_TEST_PORT:-39990}"
WEBHOOK_SECRET="${ORCHIVISTE_WEBHOOK_TEST_SECRET:-orchiviste-smoke-secret}"
CAPTURE_FILE="$TMP_DIR/webhook_capture.json"
API_LOG="$TMP_DIR/api.log"
ANALYSE_LOG="$TMP_DIR/analyse.log"
RECEIVER_LOG="$TMP_DIR/receiver.log"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

cleanup() {
  for pid in "${API_PID:-}" "${ANALYSE_PID:-}" "${RECEIVER_PID:-}"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

need_cmd python3
need_cmd curl

echo "== Orchiviste webhook HMAC smoke test =="
echo "API port: $API_PORT, Analyse port: $ANALYSE_PORT, Webhook port: $WEBHOOK_PORT"

python3 - "$WEBHOOK_PORT" "$CAPTURE_FILE" >"$RECEIVER_LOG" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])
capture_file = sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        return

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        payload = {
            "path": self.path,
            "headers": {k.lower(): v for k, v in self.headers.items()},
            "body": body
        }
        with open(capture_file, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
        raise SystemExit(0)

HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
RECEIVER_PID=$!

(
  cd "$ROOT_DIR/OrchivisteAnalyse"
  ORCHIVISTE_ANALYSE_HOST=127.0.0.1 \
  ORCHIVISTE_ANALYSE_PORT="$ANALYSE_PORT" \
  ./.build/debug/OrchivisteAnalyse >"$ANALYSE_LOG" 2>&1
) &
ANALYSE_PID=$!

(
  cd "$ROOT_DIR/OrchivisteAPI"
  ORCHIVISTE_API_HOST=127.0.0.1 \
  ORCHIVISTE_API_PORT="$API_PORT" \
  ORCHIVISTE_AUTO_MIGRATE=1 \
  ORCHIVISTE_SQLITE_PATH="$TMP_DIR/webhook-test.sqlite" \
  ORCHIVISTE_ANALYSE_URL="http://127.0.0.1:$ANALYSE_PORT" \
  ORCHIVISTE_WEBHOOK_URL="http://127.0.0.1:$WEBHOOK_PORT/webhook" \
  ORCHIVISTE_WEBHOOK_SECRET="$WEBHOOK_SECRET" \
  ./.build/debug/OrchivisteAPI >"$API_LOG" 2>&1
) &
API_PID=$!

for _ in $(seq 1 60); do
  if curl -sS "http://127.0.0.1:$API_PORT/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -sS -X POST "http://127.0.0.1:$API_PORT/v1/ingest" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: webhook-smoke-$(date +%s)" \
  -d '{"fileURL":"webhook-smoke.pdf","source":{"kind":"local"},"tags":["webhook"]}' >/dev/null

for _ in $(seq 1 40); do
  if [[ -f "$CAPTURE_FILE" ]]; then
    break
  fi
  sleep 0.25
done

if [[ ! -f "$CAPTURE_FILE" ]]; then
  echo "FAIL: no webhook payload captured" >&2
  tail -n 80 "$API_LOG" >&2 || true
  tail -n 80 "$ANALYSE_LOG" >&2 || true
  exit 1
fi

python3 - "$CAPTURE_FILE" "$WEBHOOK_SECRET" <<'PY'
import hashlib
import hmac
import json
import sys

capture_file = sys.argv[1]
secret = sys.argv[2].encode("utf-8")

with open(capture_file, "r", encoding="utf-8") as f:
    payload = json.load(f)

headers = payload["headers"]
body = payload["body"].encode("utf-8")

ts = headers.get("x-orchiviste-timestamp", "")
sig = headers.get("x-orchiviste-signature", "")
event_type = headers.get("x-orchiviste-event-type", "")
event_id = headers.get("x-orchiviste-event-id", "")

if not ts or not sig:
    print("FAIL: missing HMAC headers")
    sys.exit(1)
if not sig.startswith("sha256="):
    print("FAIL: signature prefix mismatch")
    sys.exit(1)
if not event_type or not event_id:
    print("FAIL: missing event metadata headers")
    sys.exit(1)

expected = hmac.new(secret, ts.encode("utf-8") + b"." + body, hashlib.sha256).hexdigest()
actual = sig.split("=", 1)[1]
if not hmac.compare_digest(expected, actual):
    print("FAIL: invalid signature")
    sys.exit(1)

print("OK  webhook signature valid")
print(f"OK  event metadata type={event_type} id={event_id}")
PY

echo "Webhook HMAC smoke test passed."
