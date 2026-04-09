#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

API_PORT="${ORCHIVISTE_COCKPIT_SMOKE_API_PORT:-}"
API_LOG="$TMP_DIR/api.log"
CONFIG_FILE="$TMP_DIR/cockpit.config.json"
STUB_TOOL="$TMP_DIR/smoke-tool.py"

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
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

cleanup() {
  if [[ -n "${API_PID:-}" ]]; then
    kill "$API_PID" >/dev/null 2>&1 || true
    wait "$API_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

assert_code() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local file="$4"
  if [[ "$actual" != "$expected" ]]; then
    echo "ECHEC [$label] HTTP attendu $expected, reçu $actual" >&2
    [[ -f "$file" ]] && cat "$file" >&2
    exit 1
  fi
}

http_json() {
  local method="$1"
  local url="$2"
  local body_file="$3"
  local out_file="$4"
  local code
  if [[ -n "$body_file" ]]; then
    code="$(curl -sS -o "$out_file" -w "%{http_code}" -X "$method" "$url" -H "Content-Type: application/json" --data-binary "@$body_file")"
  else
    code="$(curl -sS -o "$out_file" -w "%{http_code}" -X "$method" "$url")"
  fi
  echo "$code"
}

need_cmd curl
need_cmd python3

if [[ -z "$API_PORT" ]]; then
  API_PORT="$(pick_port)"
fi

cat > "$STUB_TOOL" <<'PY'
#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timezone

args = sys.argv[1:]
if len(args) != 5 or args[0] != "run" or args[1] != "--request" or args[3] != "--result":
    print("invalid args", file=sys.stderr)
    sys.exit(2)

request_path = args[2]
result_path = args[4]

with open(request_path, "r", encoding="utf-8") as f:
    request = json.load(f)

now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
result = {
    "schema_version": request.get("schema_version", "1.0"),
    "request_id": request["request_id"],
    "tool": request.get("tool", "SmokeTool"),
    "status": "succeeded",
    "started_at": now,
    "finished_at": now,
    "progress_events": [
        {
            "request_id": request["request_id"],
            "status": "running",
            "stage": "smoke",
            "percent": 10,
            "message": "Smoke execution started.",
            "occurred_at": now,
            "metadata": {}
        },
        {
            "request_id": request["request_id"],
            "status": "succeeded",
            "stage": "smoke_complete",
            "percent": 100,
            "message": "Smoke execution completed.",
            "occurred_at": now,
            "metadata": {}
        }
    ],
    "output_artifacts": [],
    "errors": [],
    "summary": "Smoke tool completed successfully.",
    "metadata": {
        "dry_run": request.get("parameters", {}).get("dry_run", True),
        "regles_source": "muniregles_bundle",
        "regles_bundle_version": "0.1.0",
        "regles_module_version": "0.1.0",
        "regles_rule_id": "rule-smoke",
        "warnings": [
            {
                "code": "SMOKE_WARNING",
                "message": "Synthetic warning for cockpit diagnostics rendering."
            }
        ]
    }
}

with open(result_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
PY
chmod +x "$STUB_TOOL"

cat > "$CONFIG_FILE" <<JSON
{
  "schema_version": "1.0",
  "workspace_path": "$ROOT_DIR/..",
  "runtime_directory": "$TMP_DIR/cockpit-runtime",
  "requests_directory": "requests",
  "results_directory": "results",
  "history_file": "history.jsonl",
  "tool_timeout_seconds": 30,
  "tools": [
    {
      "id": "SmokeTool",
      "display_name": "SmokeTool",
      "mission": "Stub tool for cockpit smoke test.",
      "executable": "smoke-tool",
      "executable_path": "$STUB_TOOL",
      "version": "0.0.1",
      "integration_status": "ready",
      "capabilities": ["run", "canonical-run"],
      "default_action": "run",
      "default_parameters": {
        "dry_run": true
      },
      "supports_dry_run": true,
      "destructive_requires_confirmation": false,
      "enabled": true
    }
  ]
}
JSON

(
  cd "$ROOT_DIR/OrchivisteAPI"
  ORCHIVISTE_API_HOST=127.0.0.1 \
  ORCHIVISTE_API_PORT="$API_PORT" \
  ORCHIVISTE_AUTO_MIGRATE=1 \
  ORCHIVISTE_SQLITE_PATH="$TMP_DIR/cockpit-smoke.sqlite" \
  ORCHIVISTE_COCKPIT_CONFIG_FILE="$CONFIG_FILE" \
  ./.build/debug/OrchivisteAPI >"$API_LOG" 2>&1
) &
API_PID=$!

for _ in $(seq 1 60); do
  if ! kill -0 "$API_PID" >/dev/null 2>&1; then
    echo "ECHEC : OrchivisteAPI arrêté avant readiness." >&2
    tail -n 120 "$API_LOG" >&2 || true
    exit 1
  fi
  if curl -sS "http://127.0.0.1:$API_PORT/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

TOOLS_JSON="$TMP_DIR/tools.json"
TOOLS_CODE="$(http_json GET "http://127.0.0.1:$API_PORT/v1/cockpit/tools" "" "$TOOLS_JSON")"
assert_code "$TOOLS_CODE" "200" "cockpit.tools" "$TOOLS_JSON"
python3 - "$TOOLS_JSON" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    tools = json.load(f)
if not tools:
    raise SystemExit("ECHEC: catalogue cockpit vide")
first = tools[0]
if first.get("descriptor", {}).get("id") != "SmokeTool":
    raise SystemExit("ECHEC: SmokeTool absent du catalogue")
if not first.get("is_available"):
    raise SystemExit("ECHEC: SmokeTool non disponible")
print("OK  catalogue cockpit")
PY

RUN_REQ="$TMP_DIR/run-request.json"
cat > "$RUN_REQ" <<'JSON'
{
  "tool_id": "SmokeTool",
  "action": "run",
  "parameters": {
    "dry_run": true
  }
}
JSON

RUN_RES="$TMP_DIR/run-response.json"
RUN_CODE="$(http_json POST "http://127.0.0.1:$API_PORT/v1/cockpit/runs" "$RUN_REQ" "$RUN_RES")"
assert_code "$RUN_CODE" "200" "cockpit.runs" "$RUN_RES"
python3 - "$RUN_RES" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    payload = json.load(f)
status = payload.get("status")
if status != "succeeded":
    raise SystemExit(f"ECHEC: statut run inattendu: {status}")
if not payload.get("request_file") or not payload.get("result_file"):
    raise SystemExit("ECHEC: chemins request/result absents")
print("OK  exécution canonique cockpit")
PY

HISTORY_JSON="$TMP_DIR/history.json"
HISTORY_CODE="$(http_json GET "http://127.0.0.1:$API_PORT/v1/cockpit/history?limit=5" "" "$HISTORY_JSON")"
assert_code "$HISTORY_CODE" "200" "cockpit.history" "$HISTORY_JSON"
python3 - "$HISTORY_JSON" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    payload = json.load(f)
entries = payload.get("entries", [])
if not entries:
    raise SystemExit("ECHEC: historique cockpit vide")
if entries[0].get("status") not in {"succeeded", "needs_review", "not_implemented"}:
    raise SystemExit("ECHEC: statut historique inattendu")
print("OK  historique JSONL cockpit")
PY

UI_COCKPIT_HEADERS="$TMP_DIR/ui-cockpit.headers"
UI_COCKPIT_BODY="$TMP_DIR/ui-cockpit.body"
UI_COCKPIT_CODE="$(curl -sS -D "$UI_COCKPIT_HEADERS" -o "$UI_COCKPIT_BODY" -w "%{http_code}" "http://127.0.0.1:$API_PORT/ui/cockpit")"
assert_code "$UI_COCKPIT_CODE" "303" "ui.cockpit.redirect" "$UI_COCKPIT_BODY"
if ! grep -Ei '^location: /ui/pilotage/catalogue' "$UI_COCKPIT_HEADERS" >/dev/null; then
  echo "ECHEC [ui.cockpit.redirect] location inattendue" >&2
  cat "$UI_COCKPIT_HEADERS" >&2
  exit 1
fi

UI_PILOTAGE_HEADERS="$TMP_DIR/ui-pilotage.headers"
UI_PILOTAGE_BODY="$TMP_DIR/ui-pilotage.body"
UI_PILOTAGE_CODE="$(curl -sS -D "$UI_PILOTAGE_HEADERS" -o "$UI_PILOTAGE_BODY" -w "%{http_code}" "http://127.0.0.1:$API_PORT/ui/pilotage")"
assert_code "$UI_PILOTAGE_CODE" "303" "ui.pilotage.redirect" "$UI_PILOTAGE_BODY"
if ! grep -Ei '^location: /ui/pilotage/catalogue' "$UI_PILOTAGE_HEADERS" >/dev/null; then
  echo "ECHEC [ui.pilotage.redirect] location inattendue" >&2
  cat "$UI_PILOTAGE_HEADERS" >&2
  exit 1
fi

UI_CATALOGUE_HTML="$TMP_DIR/ui-pilotage-catalogue.html"
UI_CATALOGUE_CODE="$(curl -sS -o "$UI_CATALOGUE_HTML" -w "%{http_code}" "http://127.0.0.1:$API_PORT/ui/pilotage/catalogue")"
assert_code "$UI_CATALOGUE_CODE" "200" "ui.pilotage.catalogue" "$UI_CATALOGUE_HTML"
if ! grep -q "Catalogue des outils Muni" "$UI_CATALOGUE_HTML"; then
  echo "ECHEC [ui.pilotage.catalogue] contenu absent" >&2
  cat "$UI_CATALOGUE_HTML" >&2
  exit 1
fi

UI_LANCER_HTML="$TMP_DIR/ui-pilotage-lancer.html"
UI_LANCER_CODE="$(curl -sS -o "$UI_LANCER_HTML" -w "%{http_code}" "http://127.0.0.1:$API_PORT/ui/pilotage/lancer")"
assert_code "$UI_LANCER_CODE" "200" "ui.pilotage.lancer" "$UI_LANCER_HTML"
if ! grep -q "Lancement canonique" "$UI_LANCER_HTML"; then
  echo "ECHEC [ui.pilotage.lancer] contenu absent" >&2
  cat "$UI_LANCER_HTML" >&2
  exit 1
fi

UI_HISTORIQUE_HTML="$TMP_DIR/ui-pilotage-historique.html"
UI_HISTORIQUE_CODE="$(curl -sS -o "$UI_HISTORIQUE_HTML" -w "%{http_code}" "http://127.0.0.1:$API_PORT/ui/pilotage/historique")"
assert_code "$UI_HISTORIQUE_CODE" "200" "ui.pilotage.historique" "$UI_HISTORIQUE_HTML"
if ! grep -q "Historique local" "$UI_HISTORIQUE_HTML"; then
  echo "ECHEC [ui.pilotage.historique] contenu absent" >&2
  cat "$UI_HISTORIQUE_HTML" >&2
  exit 1
fi
if ! grep -q "Diagnostics" "$UI_HISTORIQUE_HTML"; then
  echo "ECHEC [ui.pilotage.historique] colonne diagnostics absente" >&2
  cat "$UI_HISTORIQUE_HTML" >&2
  exit 1
fi
if ! grep -q "rule-smoke" "$UI_HISTORIQUE_HTML"; then
  echo "ECHEC [ui.pilotage.historique] rule id diagnostic absent" >&2
  cat "$UI_HISTORIQUE_HTML" >&2
  exit 1
fi
if ! grep -q "SMOKE_WARNING" "$UI_HISTORIQUE_HTML"; then
  echo "ECHEC [ui.pilotage.historique] warning diagnostic absent" >&2
  cat "$UI_HISTORIQUE_HTML" >&2
  exit 1
fi

echo "Test fumée cockpit V1 réussi."
