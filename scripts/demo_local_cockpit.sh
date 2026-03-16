#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUITE_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

DEMO_HOST="${ORCHIVISTE_DEMO_HOST:-127.0.0.1}"
DEMO_PORT="${ORCHIVISTE_DEMO_PORT:-28780}"
BASE_URL="http://${DEMO_HOST}:${DEMO_PORT}"

RUNTIME_ROOT="${ORCHIVISTE_DEMO_RUNTIME_DIR:-$REPO_ROOT/runtime/demo-local}"
LOG_DIR="$RUNTIME_ROOT/logs"
REQUEST_DIR="$RUNTIME_ROOT/requests"
RESULT_DIR="$RUNTIME_ROOT/results"
PID_FILE="$RUNTIME_ROOT/orchiviste-api.pid"
API_LOG_FILE="$LOG_DIR/orchiviste-api.log"
SQLITE_PATH="${ORCHIVISTE_DEMO_SQLITE_PATH:-$RUNTIME_ROOT/orchiviste-demo.sqlite}"
COCKPIT_CONFIG_FILE="${ORCHIVISTE_DEMO_CONFIG_FILE:-$REPO_ROOT/OrchivisteAPI/configs/cockpit/demo.local.json}"
FIXTURE_FILE="${ORCHIVISTE_DEMO_FIXTURE:-$REPO_ROOT/fixtures/demo/cockpit/input_document.txt}"

MUNI_ANALYSE_DIR="${MUNI_ANALYSE_DIR:-$SUITE_ROOT/MuniAnalyse}"
MUNI_METADONNEES_DIR="${MUNI_METADONNEES_DIR:-$SUITE_ROOT/MuniMetadonnees}"
MUNI_PRECLASSEMENT_DIR="${MUNI_PRECLASSEMENT_DIR:-$SUITE_ROOT/MuniPreclassement}"
MUNI_CONTROLE_DIR="${MUNI_CONTROLE_DIR:-$SUITE_ROOT/MuniControle}"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ECHEC: commande requise manquante: $cmd" >&2
    exit 1
  fi
}

need_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "ECHEC: $label introuvable: $path" >&2
    exit 1
  fi
}

need_dir() {
  local path="$1"
  local label="$2"
  if [[ ! -d "$path" ]]; then
    echo "ECHEC: $label introuvable: $path" >&2
    exit 1
  fi
}

require_prereqs() {
  need_cmd swift
  need_cmd curl
  need_cmd python3
  need_file "$COCKPIT_CONFIG_FILE" "configuration cockpit demo"
  need_file "$FIXTURE_FILE" "fixture demo"
  need_dir "$MUNI_ANALYSE_DIR" "repo MuniAnalyse"
  need_dir "$MUNI_METADONNEES_DIR" "repo MuniMetadonnees"
  need_dir "$MUNI_PRECLASSEMENT_DIR" "repo MuniPreclassement"
  need_dir "$MUNI_CONTROLE_DIR" "repo MuniControle"
}

is_running() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

wait_health() {
  local attempts=60
  while (( attempts > 0 )); do
    if curl -sS "$BASE_URL/v1/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    attempts=$((attempts - 1))
  done
  return 1
}

ensure_api_reachable() {
  if ! curl -sS "$BASE_URL/v1/health" >/dev/null 2>&1; then
    echo "ECHEC: API indisponible sur $BASE_URL. Lance d'abord: scripts/demo_local_cockpit.sh start" >&2
    exit 1
  fi
}

build_demo_binaries() {
  echo "== Build OrchivisteAPI =="
  (cd "$REPO_ROOT/OrchivisteAPI" && swift build -c debug --product OrchivisteAPI)

  echo "== Build outils actifs (Muni) =="
  (cd "$MUNI_ANALYSE_DIR" && swift build -c debug --product muni-analyse-cli)
  (cd "$MUNI_METADONNEES_DIR" && swift build -c debug --product muni-metadonnees-cli)
  (cd "$MUNI_PRECLASSEMENT_DIR" && swift build -c debug --product muni-preclassement-cli)
  (cd "$MUNI_CONTROLE_DIR" && swift build -c debug --product muni-controle-cli)
}

cmd_start() {
  require_prereqs

  if is_running; then
    echo "OrchivisteAPI est deja en cours (PID $(cat "$PID_FILE"))."
    echo "URL: $BASE_URL/ui/cockpit"
    exit 0
  fi

  mkdir -p "$LOG_DIR" "$REQUEST_DIR" "$RESULT_DIR"

  if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    build_demo_binaries
  fi

  echo "== Demarrage OrchivisteAPI (sans Docker) =="
  local pid
  pushd "$REPO_ROOT/OrchivisteAPI" >/dev/null
  nohup env \
    ORCHIVISTE_API_HOST="$DEMO_HOST" \
    ORCHIVISTE_API_PORT="$DEMO_PORT" \
    ORCHIVISTE_AUTO_MIGRATE=1 \
    ORCHIVISTE_SQLITE_PATH="$SQLITE_PATH" \
    ORCHIVISTE_COCKPIT_CONFIG_FILE="$COCKPIT_CONFIG_FILE" \
    ./.build/debug/OrchivisteAPI \
    >"$API_LOG_FILE" 2>&1 < /dev/null &
  pid="$!"
  popd >/dev/null

  if [[ -z "$pid" ]]; then
    echo "ECHEC: impossible de recuperer le PID OrchivisteAPI." >&2
    [[ -f "$API_LOG_FILE" ]] && tail -n 80 "$API_LOG_FILE" >&2
    exit 1
  fi
  echo "$pid" > "$PID_FILE"

  if ! wait_health; then
    echo "ECHEC: API non prete sur $BASE_URL (voir $API_LOG_FILE)" >&2
    cmd_stop >/dev/null 2>&1 || true
    exit 1
  fi

  echo "API prete."
  echo "- URL cockpit: $BASE_URL/ui/cockpit"
  echo "- URL catalogue API: $BASE_URL/v1/cockpit/tools"
  echo "- PID file: $PID_FILE"
  echo "- Log API: $API_LOG_FILE"
  echo "- SQLite: $SQLITE_PATH"
  echo "- Runtime cockpit: $REPO_ROOT/runtime/demo-local/cockpit"
}

cmd_catalog() {
  require_prereqs
  ensure_api_reachable
  local out="$RESULT_DIR/catalog.tools.json"
  mkdir -p "$RESULT_DIR"
  curl -sS "$BASE_URL/v1/cockpit/tools" > "$out"
  python3 - <<'PY' "$out"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    tools = json.load(f)
print("Catalogue outils:")
for item in tools:
    d = item.get("descriptor", {})
    print(f"- {d.get('id')} v{d.get('version')} status={d.get('integration_status')} available={item.get('is_available')}")
PY
  echo "JSON complet: $out"
}

cmd_sample_run() {
  require_prereqs
  ensure_api_reachable
  mkdir -p "$REQUEST_DIR" "$RESULT_DIR"

  local payload="$REQUEST_DIR/demo-run-muni-analyse.payload.json"
  local response="$RESULT_DIR/demo-run-muni-analyse.response.json"
  local report_path="$RESULT_DIR/demo-run-muni-analyse.report.json"

  cat > "$payload" <<JSON
{
  "tool_id": "MuniAnalyse",
  "action": "run",
  "parameters": {
    "source_path": "$FIXTURE_FILE",
    "report_path": "$report_path"
  }
}
JSON

  curl -sS -X POST "$BASE_URL/v1/cockpit/runs" \
    -H "Content-Type: application/json" \
    --data-binary "@$payload" \
    > "$response"

  python3 - <<'PY' "$response" "$report_path"
import json, sys, os
resp = json.load(open(sys.argv[1], 'r', encoding='utf-8'))
report_path = sys.argv[2]
status = resp.get('status')
if status not in {'succeeded', 'needs_review'}:
    raise SystemExit(f"ECHEC run: statut inattendu {status}")
print(f"Run OK: status={status}")
print(f"Execution ID: {resp.get('execution_id')}")
print(f"Request file: {resp.get('request_file')}")
print(f"Result file: {resp.get('result_file')}")
print(f"History file: {resp.get('history_file')}")
print(f"Report exists: {os.path.exists(report_path)} ({report_path})")
PY

  echo "Payload: $payload"
  echo "Reponse: $response"
}

cmd_history() {
  require_prereqs
  ensure_api_reachable
  local out="$RESULT_DIR/history.latest.json"
  mkdir -p "$RESULT_DIR"
  curl -sS "$BASE_URL/v1/cockpit/history?limit=20" > "$out"
  python3 - <<'PY' "$out"
import json, sys
payload = json.load(open(sys.argv[1], 'r', encoding='utf-8'))
entries = payload.get('entries', [])
print(f"Historique ({len(entries)} entree(s))")
for e in entries[:10]:
    print(f"- {e.get('started_at')} | {e.get('tool_id')} | {e.get('action')} | {e.get('status')} | {e.get('execution_id')}")
print(f"history_file={payload.get('history_file')}")
PY
  echo "JSON complet: $out"
}

cmd_status() {
  if is_running; then
    local pid
    pid="$(cat "$PID_FILE")"
    echo "API en cours (PID $pid)."
  else
    echo "API arretee."
  fi

  if curl -sS "$BASE_URL/v1/health" >/dev/null 2>&1; then
    echo "Health endpoint OK: $BASE_URL/v1/health"
  else
    echo "Health endpoint indisponible: $BASE_URL/v1/health"
  fi

  echo "Cockpit UI: $BASE_URL/ui/cockpit"
}

cmd_stop() {
  if ! is_running; then
    echo "API deja arretee."
    rm -f "$PID_FILE"
    return 0
  fi

  local pid
  pid="$(cat "$PID_FILE")"
  echo "Arret API (PID $pid)..."
  kill "$pid" >/dev/null 2>&1 || true

  local attempts=20
  while kill -0 "$pid" >/dev/null 2>&1 && (( attempts > 0 )); do
    sleep 0.5
    attempts=$((attempts - 1))
  done

  if kill -0 "$pid" >/dev/null 2>&1; then
    echo "Force kill PID $pid"
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi

  rm -f "$PID_FILE"
  echo "API arretee."
}

cmd_demo_once() {
  echo "== Demo locale Orchiviste (sans Docker) =="
  cmd_start
  trap 'cmd_stop >/dev/null 2>&1 || true' EXIT
  cmd_catalog
  cmd_sample_run
  cmd_history
  echo "Demo locale terminee."
}

usage() {
  cat <<'TXT'
Usage:
  scripts/demo_local_cockpit.sh start
  scripts/demo_local_cockpit.sh status
  scripts/demo_local_cockpit.sh catalog
  scripts/demo_local_cockpit.sh sample-run
  scripts/demo_local_cockpit.sh history
  scripts/demo_local_cockpit.sh stop
  scripts/demo_local_cockpit.sh demo-once

Variables utiles:
  ORCHIVISTE_DEMO_HOST           (defaut: 127.0.0.1)
  ORCHIVISTE_DEMO_PORT           (defaut: 28780)
  ORCHIVISTE_DEMO_RUNTIME_DIR    (defaut: Orchiviste/runtime/demo-local)
  ORCHIVISTE_DEMO_SQLITE_PATH    (defaut: runtime/demo-local/orchiviste-demo.sqlite)
  ORCHIVISTE_DEMO_CONFIG_FILE    (defaut: OrchivisteAPI/configs/cockpit/demo.local.json)
  ORCHIVISTE_DEMO_FIXTURE        (defaut: fixtures/demo/cockpit/input_document.txt)
  MUNI_ANALYSE_DIR               (defaut: ../MuniAnalyse)
  MUNI_METADONNEES_DIR           (defaut: ../MuniMetadonnees)
  MUNI_PRECLASSEMENT_DIR         (defaut: ../MuniPreclassement)
  MUNI_CONTROLE_DIR              (defaut: ../MuniControle)
  SKIP_BUILD=1                   (skip des builds)
TXT
}

main() {
  local cmd="${1:-start}"
  case "$cmd" in
    start) cmd_start ;;
    status) cmd_status ;;
    catalog) cmd_catalog ;;
    sample-run) cmd_sample_run ;;
    history) cmd_history ;;
    stop) cmd_stop ;;
    demo-once) cmd_demo_once ;;
    -h|--help|help) usage ;;
    *)
      echo "Commande inconnue: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
