#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

API_PORT="${ORCHIVISTE_GRAPH_TEST_API_PORT:-}"
ANALYSE_PORT="${ORCHIVISTE_GRAPH_TEST_ANALYSE_PORT:-}"
MOCK_PORT="${ORCHIVISTE_GRAPH_TEST_MOCK_PORT:-}"
REDIS_URL="${ORCHIVISTE_GRAPH_TEST_REDIS_URL:-redis://127.0.0.1:6379}"
CONFIG_DIR="$TMP_DIR/configs"
STATE_FILE="$TMP_DIR/mock-graph-state.json"
API_LOG="$TMP_DIR/api.log"
ANALYSE_LOG="$TMP_DIR/analyse.log"
MOCK_LOG="$TMP_DIR/mock.log"

cleanup() {
  for pid in "${API_PID:-}" "${ANALYSE_PID:-}" "${MOCK_PID:-}"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Commande requise manquante : $cmd" >&2
    exit 1
  fi
}

pick_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

json_get() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    payload = json.load(f)

current = payload
for part in sys.argv[2].split("."):
    if isinstance(current, dict):
        current = current.get(part)
    elif isinstance(current, list) and part.isdigit():
        idx = int(part)
        current = current[idx] if 0 <= idx < len(current) else None
    else:
        current = None
        break

if current is None:
    print("")
elif isinstance(current, (dict, list)):
    print(json.dumps(current, ensure_ascii=False))
else:
    print(current)
PY
}

need_cmd curl
need_cmd python3

if [[ -z "$API_PORT" ]]; then
  API_PORT="$(pick_port)"
fi
if [[ -z "$ANALYSE_PORT" ]]; then
  ANALYSE_PORT="$(pick_port)"
fi
if [[ -z "$MOCK_PORT" ]]; then
  MOCK_PORT="$(pick_port)"
fi

mkdir -p "$CONFIG_DIR/analysis/routing" "$CONFIG_DIR/presets"
cat >"$CONFIG_DIR/analysis/routing/routing.map.json" <<'JSON'
{
  "mappings": {
    "FIN-001": {
      "site": "site-finances",
      "library": "Documents",
      "folder_expr": "Archives/{year}/{code}",
      "metadata": {
        "Departement": "Finances"
      }
    }
  }
}
JSON

echo "== Test fumée routage SharePoint Graph =="
echo "Ports : API=$API_PORT Analyse=$ANALYSE_PORT MockGraph=$MOCK_PORT"

python3 - "$MOCK_PORT" "$STATE_FILE" >"$MOCK_LOG" 2>&1 <<'PY' &
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

port = int(sys.argv[1])
state_path = sys.argv[2]

state = {
    "folders": {},
    "next_folder_index": 1,
    "copy_requests": [],
    "delete_requests": [],
    "operation_polls": 0,
    "copied_item": {
        "id": "copied-1",
        "name": "",
        "webUrl": ""
    }
}

def save_state():
    with open(state_path, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)

def read_json(handler):
    length = int(handler.headers.get("Content-Length", "0"))
    raw = handler.rfile.read(length) if length else b""
    return json.loads(raw.decode("utf-8") or "{}")

def send_json(handler, status, payload, headers=None):
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    if headers:
      for key, value in headers.items():
        handler.send_header(key, value)
    handler.end_headers()
    handler.wfile.write(body)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        return

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path.endswith("/oauth2/v2.0/token"):
            save_state()
            return send_json(self, 200, {"access_token": "mock-token"})

        if parsed.path == "/v1.0/drives/drive-target/items/root/children" or parsed.path.startswith("/v1.0/drives/drive-target/items/folder-"):
            body = read_json(self)
            parent_id = parsed.path.split("/items/", 1)[1].split("/children", 1)[0]
            folder_name = body.get("name", "Folder")
            key = f"{parent_id}:{folder_name}"
            if key not in state["folders"]:
                state["folders"][key] = f"folder-{state['next_folder_index']}"
                state["next_folder_index"] += 1
            folder_id = state["folders"][key]
            save_state()
            return send_json(self, 201, {"id": folder_id, "name": folder_name, "webUrl": f"https://tenant.sharepoint.com/{folder_id}"})

        if parsed.path == "/v1.0/drives/drive-source/items/src-item-1/copy":
            body = read_json(self)
            state["copy_requests"].append(body)
            file_name = body.get("name", "")
            state["copied_item"] = {
                "id": "copied-1",
                "name": file_name,
                "webUrl": f"https://tenant.sharepoint.com/sites/site-finances/Documents/{file_name}"
            }
            save_state()
            self.send_response(202)
            self.send_header("Location", f"http://127.0.0.1:{port}/operations/op-1")
            self.end_headers()
            return

        return send_json(self, 404, {"error": {"message": f"Unhandled POST {self.path}"}})

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/v1.0/sites/source-site/drives":
            return send_json(self, 200, {"value": [{"id": "drive-source", "name": "SourceDocs"}]})
        if parsed.path == "/v1.0/sites/site-finances/drives":
            return send_json(self, 200, {"value": [{"id": "drive-target", "name": "Documents"}]})
        if parsed.path == "/operations/op-1":
            state["operation_polls"] += 1
            save_state()
            if state["operation_polls"] < 2:
                return send_json(self, 200, {"status": "inProgress"})
            return send_json(self, 200, {"status": "completed", "resourceId": "copied-1"})
        if parsed.path == "/v1.0/drives/drive-target/items/copied-1":
            save_state()
            return send_json(self, 200, state["copied_item"])
        if parsed.path == "/__state":
            save_state()
            return send_json(self, 200, state)
        return send_json(self, 404, {"error": {"message": f"Unhandled GET {self.path}"}})

    def do_DELETE(self):
        parsed = urlparse(self.path)
        if parsed.path == "/v1.0/drives/drive-source/items/src-item-1":
            state["delete_requests"].append(parsed.path)
            save_state()
            self.send_response(204)
            self.end_headers()
            return
        return send_json(self, 404, {"error": {"message": f"Unhandled DELETE {self.path}"}})

save_state()
HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
MOCK_PID=$!

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
  ORCHIVISTE_SQLITE_PATH="$TMP_DIR/graph-test.sqlite" \
  ORCHIVISTE_ANALYSE_URL="http://127.0.0.1:$ANALYSE_PORT" \
  ORCHIVISTE_CONFIG_DIR="$CONFIG_DIR" \
  ORCHIVISTE_REDIS_URL="$REDIS_URL" \
  ORCHIVISTE_REDIS_INGEST_KEY="orchiviste:test:graph:ingest" \
  ORCHIVISTE_REDIS_DEADLETTER_KEY="orchiviste:test:graph:dead" \
  ORCHIVISTE_GRAPH_ENABLED=1 \
  ORCHIVISTE_GRAPH_TENANT_ID="tenant-test" \
  ORCHIVISTE_GRAPH_CLIENT_ID="client-test" \
  ORCHIVISTE_GRAPH_CLIENT_SECRET="secret-test" \
  ORCHIVISTE_GRAPH_BASE_URL="http://127.0.0.1:$MOCK_PORT/v1.0" \
  ORCHIVISTE_GRAPH_AUTH_BASE_URL="http://127.0.0.1:$MOCK_PORT" \
  ORCHIVISTE_GRAPH_COPY_TIMEOUT_MS=5000 \
  ORCHIVISTE_GRAPH_COPY_POLL_INTERVAL_MS=150 \
  ORCHIVISTE_GRAPH_DELETE_SOURCE_AFTER_COPY=1 \
  ./.build/debug/OrchivisteAPI >"$API_LOG" 2>&1
) &
API_PID=$!

for _ in $(seq 1 60); do
  if ! kill -0 "$MOCK_PID" >/dev/null 2>&1; then
    echo "ECHEC : le mock Graph s'est arrêté pendant le démarrage." >&2
    tail -n 120 "$MOCK_LOG" >&2 || true
    exit 1
  fi
  if ! kill -0 "$ANALYSE_PID" >/dev/null 2>&1; then
    echo "ECHEC : OrchivisteAnalyse s'est arrêté pendant le démarrage du smoke Graph." >&2
    tail -n 120 "$ANALYSE_LOG" >&2 || true
    exit 1
  fi
  if ! kill -0 "$API_PID" >/dev/null 2>&1; then
    echo "ECHEC : OrchivisteAPI s'est arrêté pendant le démarrage du smoke Graph." >&2
    tail -n 120 "$API_LOG" >&2 || true
    tail -n 120 "$ANALYSE_LOG" >&2 || true
    exit 1
  fi
  if curl -sS "http://127.0.0.1:$API_PORT/v1/health" >/dev/null 2>&1 \
    && curl -sS "http://127.0.0.1:$ANALYSE_PORT/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

ingest_payload="$TMP_DIR/graph-ingest.json"
cat >"$ingest_payload" <<'JSON'
{
  "fileURL": "https://tenant.sharepoint.com/sites/source-site/SourceDocs/Facture_2024-015_Acme.pdf",
  "source": {
    "kind": "sharepoint",
    "url": "https://tenant.sharepoint.com/sites/source-site/SourceDocs/Facture_2024-015_Acme.pdf",
    "site": "source-site",
    "library": "SourceDocs",
    "itemId": "src-item-1"
  },
  "tags": ["graph", "facture"]
}
JSON

ingest_response="$TMP_DIR/graph-ingest-response.json"
ingest_code="$(curl -sS -o "$ingest_response" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: graph-smoke-$(date +%s)" \
  -X POST "http://127.0.0.1:$API_PORT/v1/ingest" \
  --data-binary "@$ingest_payload")"
if [[ "$ingest_code" != "202" ]]; then
  echo "ECHEC : ingest Graph HTTP $ingest_code" >&2
  cat "$ingest_response" >&2 || true
  exit 1
fi

job_id="$(json_get "$ingest_response" "taskId")"
if [[ -z "$job_id" ]]; then
  echo "ECHEC : taskId absent après ingest Graph" >&2
  cat "$ingest_response" >&2 || true
  exit 1
fi

job_response="$TMP_DIR/job.json"
job_status=""
for _ in $(seq 1 80); do
  job_code="$(curl -sS -o "$job_response" -w "%{http_code}" "http://127.0.0.1:$API_PORT/v1/jobs/$job_id")"
  if [[ "$job_code" != "200" ]]; then
    sleep 0.5
    continue
  fi
  job_status="$(json_get "$job_response" "status")"
  if [[ "$job_status" == "completed" || "$job_status" == "needs_review" || "$job_status" == "failed" ]]; then
    break
  fi
  sleep 0.5
done

if [[ "$job_status" == "failed" || -z "$job_status" ]]; then
  echo "ECHEC : le job Graph n'a pas atteint un état routable" >&2
  cat "$job_response" >&2 || true
  tail -n 120 "$API_LOG" >&2 || true
  tail -n 120 "$ANALYSE_LOG" >&2 || true
  exit 1
fi

if [[ "$job_status" == "needs_review" ]]; then
  review_payload="$TMP_DIR/review.json"
  cat >"$review_payload" <<'JSON'
{
  "corrected_class_code": "FIN-001",
  "comment": "Smoke Graph review override"
}
JSON
  review_response="$TMP_DIR/review-response.json"
  review_code="$(curl -sS -o "$review_response" -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -X POST "http://127.0.0.1:$API_PORT/v1/jobs/$job_id/review" \
    --data-binary "@$review_payload")"
  if [[ "$review_code" != "200" ]]; then
    echo "ECHEC : review Graph HTTP $review_code" >&2
    cat "$review_response" >&2 || true
    exit 1
  fi
fi

route_payload="$TMP_DIR/route.json"
cat >"$route_payload" <<'JSON'
{
  "class_code": "FIN-001",
  "name_format": "{class_code}-{type_doc}-{original}"
}
JSON

route_response="$TMP_DIR/route-response.json"
route_code="$(curl -sS -o "$route_response" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -X POST "http://127.0.0.1:$API_PORT/v1/route/$job_id" \
  --data-binary "@$route_payload")"
if [[ "$route_code" != "200" ]]; then
  echo "ECHEC : route Graph HTTP $route_code" >&2
  cat "$route_response" >&2 || true
  tail -n 120 "$API_LOG" >&2 || true
  cat "$STATE_FILE" >&2 || true
  exit 1
fi

python3 - "$route_response" "$STATE_FILE" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    route_payload = json.load(f)
with open(sys.argv[2], "r", encoding="utf-8") as f:
    state = json.load(f)

mode = route_payload.get("mode")
if mode != "graph":
    raise SystemExit(f"ECHEC : mode attendu graph, reçu {mode}")

moved_item_id = route_payload.get("moved_item_id") or ""
if not moved_item_id:
    raise SystemExit("ECHEC : moved_item_id absent")

resolved_file_name = route_payload.get("resolved_file_name") or ""
if not resolved_file_name:
    raise SystemExit("ECHEC : resolved_file_name absent")
if re.fullmatch(r"FIN-001-\d{8}-\d{6}\.pdf", resolved_file_name):
    raise SystemExit(f"ECHEC : nom Graph trop générique : {resolved_file_name}")
if "Facture_2024-015_Acme" not in resolved_file_name:
    raise SystemExit(f"ECHEC : nom Graph non significatif : {resolved_file_name}")

destination_url = route_payload.get("destination_url") or ""
if "site-finances" not in destination_url or "Documents" not in destination_url:
    raise SystemExit(f"ECHEC : destination_url inattendue : {destination_url}")

copy_requests = state.get("copy_requests") or []
if not copy_requests:
    raise SystemExit("ECHEC : aucune copie Graph enregistrée par le mock")
if copy_requests[-1].get("name") != resolved_file_name:
    raise SystemExit("ECHEC : le nom transmis à Graph ne correspond pas au nom résolu")

delete_requests = state.get("delete_requests") or []
if not delete_requests:
    raise SystemExit("ECHEC : la suppression de la source après copie n'a pas été appelée")

if int(state.get("operation_polls") or 0) < 1:
    raise SystemExit("ECHEC : l'opération de copie Graph n'a pas été pollée")

print("OK  routage Graph cross-drive/cross-site")
print(f"OK  nom final = {resolved_file_name}")
PY

echo "Test fumée routage SharePoint Graph réussi."
