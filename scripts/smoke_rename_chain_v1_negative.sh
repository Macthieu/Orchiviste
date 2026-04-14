#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHIVISTE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SUITE_ROOT="$(cd "$ORCHIVISTE_DIR/.." && pwd)"

ORCHIVISTE_API_DIR="$ORCHIVISTE_DIR/OrchivisteAPI"
MUNI_ANALYSE_DIR="${MUNI_ANALYSE_DIR:-$SUITE_ROOT/MuniAnalyse}"
MUNI_REGLES_DIR="${MUNI_REGLES_DIR:-$SUITE_ROOT/MuniRegles}"
MUNI_RENOMMAGE_DIR="${MUNI_RENOMMAGE_DIR:-$SUITE_ROOT/MuniRenommage}"

CLASSIFICATION_FIXTURE="$ORCHIVISTE_DIR/fixtures/demo/renommage_auto_v1/10_regles_inputs/classification_plan.json"
RULES_FIXTURE="$ORCHIVISTE_DIR/fixtures/demo/renommage_auto_v1/10_regles_inputs/naming_and_routing_rules.json"
GUIDE_FIXTURE="$ORCHIVISTE_DIR/fixtures/demo/renommage_auto_v1/10_regles_inputs/renaming_guide.json"
PRESET_FIXTURE="$ORCHIVISTE_DIR/fixtures/demo/renommage_auto_v1/30_presets/munirenommage_demo_neutre.json"
RESOLUTION_SOURCE_FIXTURE="$ORCHIVISTE_DIR/fixtures/regression/analyse/01-resolution-simple.json"
AGENDA_SOURCE_FIXTURE="$ORCHIVISTE_DIR/fixtures/regression/analyse/04-proces-verbal-simple.json"

SKIP_BUILD="${SKIP_BUILD:-0}"
KEEP_TMP="${KEEP_TMP:-0}"
API_PORT="${ORCHIVISTE_SMOKE_RENAME_NEG_PORT:-}"
API_HOST="${ORCHIVISTE_SMOKE_RENAME_NEG_HOST:-127.0.0.1}"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ECHEC: commande requise introuvable: $cmd" >&2
    exit 1
  fi
}

need_dir() {
  local path="$1"
  local label="$2"
  if [[ ! -d "$path" ]]; then
    echo "ECHEC: repertoire manquant pour $label: $path" >&2
    exit 1
  fi
}

need_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "ECHEC: fichier manquant pour $label: $path" >&2
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

log_step() {
  echo
  echo "== $1 =="
}

extract_json_field() {
  local json_file="$1"
  local field="$2"
  python3 - "$json_file" "$field" <<'PY'
import json
import sys

json_file, field = sys.argv[1:3]
with open(json_file, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

value = payload
for part in field.split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if value is None:
    raise SystemExit(f"missing field: {field}")
if isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False))
else:
    print(value)
PY
}

http_json() {
  local method="$1"
  local url="$2"
  local payload_file="$3"
  local output_file="$4"
  local code

  if [[ -n "$payload_file" ]]; then
    code="$(curl -sS -o "$output_file" -w "%{http_code}" -X "$method" "$url" -H "Content-Type: application/json" --data-binary "@$payload_file")"
  else
    code="$(curl -sS -o "$output_file" -w "%{http_code}" -X "$method" "$url")"
  fi
  echo "$code"
}

assert_http_code() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local body_file="$4"
  if [[ "$actual" != "$expected" ]]; then
    echo "ECHEC [$label] HTTP attendu $expected, recu $actual" >&2
    [[ -f "$body_file" ]] && cat "$body_file" >&2
    exit 1
  fi
}

assert_run_response() {
  local response_file="$1"
  local expected_tool="$2"
  local expected_action="$3"
  python3 - "$response_file" "$expected_tool" "$expected_action" <<'PY'
import json
import os
import sys

response_file, expected_tool, expected_action = sys.argv[1:4]
with open(response_file, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

if payload.get("tool_id") != expected_tool:
    raise SystemExit(f"tool_id mismatch: {payload.get('tool_id')} != {expected_tool}")
if payload.get("action") != expected_action:
    raise SystemExit(f"action mismatch: {payload.get('action')} != {expected_action}")

for key in ("execution_id", "request_file", "result_file", "history_file"):
    value = payload.get(key)
    if not value or not isinstance(value, str):
        raise SystemExit(f"missing {key} in run response")
    if key.endswith("_file") and not os.path.exists(value):
        raise SystemExit(f"{key} path does not exist: {value}")
PY
}

assert_fallback_diagnostics() {
  local result_file="$1"
  local label="$2"
  python3 - "$result_file" "$label" <<'PY'
import json
import sys

result_file, label = sys.argv[1:3]
with open(result_file, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

status = payload.get("status")
if status not in {"succeeded", "needs_review"}:
    raise SystemExit(f"{label}: unexpected status={status}")

metadata = payload.get("metadata") or {}
source = metadata.get("regles_source")
reason = str(metadata.get("regles_fallback_reason", "")).strip()
if source != "fallback_local":
    raise SystemExit(f"{label}: regles_source expected fallback_local, got {source}")
if not reason:
    raise SystemExit(f"{label}: regles_fallback_reason missing")

summary = str(payload.get("summary", "")).strip()
if not summary:
    raise SystemExit(f"{label}: summary missing")
PY
}

assert_failure_with_nonzero_exit() {
  local response_file="$1"
  local label="$2"
  python3 - "$response_file" "$label" <<'PY'
import json
import sys

response_file, label = sys.argv[1:3]
with open(response_file, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

status = payload.get("status")
if status != "failed":
    raise SystemExit(f"{label}: expected status=failed, got {status}")

exit_code = payload.get("exit_code")
if exit_code is None:
    raise SystemExit(f"{label}: exit_code missing")
if int(exit_code) == 0:
    raise SystemExit(f"{label}: exit_code must be non-zero")

result_file = payload.get("result_file")
if not result_file:
    raise SystemExit(f"{label}: result_file missing")
with open(result_file, "r", encoding="utf-8") as handle:
    result = json.load(handle)

errors = result.get("errors") or []
if not errors:
    raise SystemExit(f"{label}: expected explicit errors in result payload")
PY
}

assert_http_400_guard() {
  local response_file="$1"
  python3 - "$response_file" <<'PY'
import json
import sys

response_file = sys.argv[1]
with open(response_file, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

reason = str(payload.get("reason", "")).strip()
if "allow_destructive=true" not in reason:
    raise SystemExit(f"unexpected guard reason: {reason}")
PY
}

assert_files_unchanged() {
  local source_dir="$1"
  python3 - "$source_dir" <<'PY'
import os
import sys

source_dir = sys.argv[1]
expected = sorted(["ordre-du-jour-demo.pdf", "resolution-demo.pdf"])
actual = sorted([
    name for name in os.listdir(source_dir)
    if os.path.isfile(os.path.join(source_dir, name))
])
if expected != actual:
    raise SystemExit(f"source files changed unexpectedly: expected={expected}, actual={actual}")
PY
}

assert_history_contains() {
  local history_file="$1"
  shift
  python3 - "$history_file" "$@" <<'PY'
import json
import sys

history_file = sys.argv[1]
required_ids = sys.argv[2:]
with open(history_file, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

entries = payload.get("entries") or []
by_exec = {entry.get("execution_id"): entry for entry in entries}
for execution_id in required_ids:
    if execution_id not in by_exec:
        raise SystemExit(f"execution id missing in history: {execution_id}")
PY
}

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orchiviste-rename-chain-v1-neg-XXXXXX")"
API_LOG="$TMP_DIR/orchiviste-api.log"
SQLITE_PATH="$TMP_DIR/orchiviste-smoke.sqlite"
COCKPIT_CONFIG="$TMP_DIR/cockpit.config.json"
SOURCE_DIR="$TMP_DIR/source_docs"
ARTIFACT_DIR="$TMP_DIR/artifacts"
REQUESTS_DIR="$TMP_DIR/requests"
RESPONSES_DIR="$TMP_DIR/responses"

cleanup() {
  if [[ -n "${API_PID:-}" ]]; then
    kill "$API_PID" >/dev/null 2>&1 || true
    wait "$API_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

need_cmd swift
need_cmd curl
need_cmd python3

need_dir "$ORCHIVISTE_API_DIR" "OrchivisteAPI"
need_dir "$MUNI_ANALYSE_DIR" "MuniAnalyse"
need_dir "$MUNI_REGLES_DIR" "MuniRegles"
need_dir "$MUNI_RENOMMAGE_DIR" "MuniRenommage"

need_file "$CLASSIFICATION_FIXTURE" "classification fixture"
need_file "$RULES_FIXTURE" "rules fixture"
need_file "$GUIDE_FIXTURE" "guide fixture"
need_file "$PRESET_FIXTURE" "preset fixture"
need_file "$RESOLUTION_SOURCE_FIXTURE" "resolution fixture"
need_file "$AGENDA_SOURCE_FIXTURE" "agenda fixture"

mkdir -p "$SOURCE_DIR" "$ARTIFACT_DIR" "$REQUESTS_DIR" "$RESPONSES_DIR"

if [[ -z "$API_PORT" ]]; then
  API_PORT="$(pick_port)"
fi
BASE_URL="http://${API_HOST}:${API_PORT}"

log_step "Preparation des sources demo"
RESOLUTION_DOC="$SOURCE_DIR/resolution-demo.pdf"
AGENDA_DOC="$SOURCE_DIR/ordre-du-jour-demo.pdf"
python3 - "$RESOLUTION_SOURCE_FIXTURE" "$RESOLUTION_DOC" "$AGENDA_SOURCE_FIXTURE" "$AGENDA_DOC" <<'PY'
import json
import sys

resolution_fixture, resolution_out, agenda_fixture, agenda_out = sys.argv[1:5]
with open(resolution_fixture, "r", encoding="utf-8") as handle:
    resolution = json.load(handle)
with open(agenda_fixture, "r", encoding="utf-8") as handle:
    agenda = json.load(handle)

resolution_text = resolution.get("request", {}).get("text", "")
agenda_text = agenda.get("request", {}).get("text", "")
if not resolution_text.strip() or not agenda_text.strip():
    raise SystemExit("fixture text is empty")

with open(resolution_out, "w", encoding="utf-8") as handle:
    handle.write(resolution_text.strip() + "\n")
with open(agenda_out, "w", encoding="utf-8") as handle:
    handle.write(agenda_text.strip() + "\n")
PY

if [[ "$SKIP_BUILD" != "1" ]]; then
  log_step "Build OrchivisteAPI + outils chain"
  (cd "$ORCHIVISTE_API_DIR" && swift build -c debug --product OrchivisteAPI)
  (cd "$MUNI_ANALYSE_DIR" && swift build -c debug --product muni-analyse-cli)
  (cd "$MUNI_REGLES_DIR" && swift build -c debug --product muni-regles-cli)
  (cd "$MUNI_RENOMMAGE_DIR" && swift build -c debug --product munirename-cli)
fi

cat > "$COCKPIT_CONFIG" <<JSON
{
  "schema_version": "1.0",
  "workspace_path": "$SUITE_ROOT",
  "runtime_directory": "$TMP_DIR/cockpit-runtime",
  "requests_directory": "requests",
  "results_directory": "results",
  "history_file": "history.jsonl",
  "tool_timeout_seconds": 120,
  "tools": [
    {
      "id": "MuniAnalyse",
      "display_name": "MuniAnalyse",
      "mission": "Extraction metadata deterministe.",
      "repository_path": "$MUNI_ANALYSE_DIR",
      "executable": "muni-analyse-cli",
      "version": "0.2.0",
      "integration_status": "active",
      "capabilities": ["run", "extract_document_metadata", "canonical-run"],
      "default_action": "run",
      "default_parameters": {},
      "supports_dry_run": false,
      "destructive_requires_confirmation": false,
      "enabled": true
    },
    {
      "id": "MuniRegles",
      "display_name": "MuniRegles",
      "mission": "Bundle de regles documentaire.",
      "repository_path": "$MUNI_REGLES_DIR",
      "executable": "muni-regles-cli",
      "version": "0.1.0",
      "integration_status": "alpha",
      "capabilities": ["validate", "bundle", "inspect", "canonical-run"],
      "default_action": "run",
      "default_parameters": {},
      "supports_dry_run": false,
      "destructive_requires_confirmation": false,
      "enabled": true
    },
    {
      "id": "MuniRenommage",
      "display_name": "MuniRenommage",
      "mission": "Renommage canonique.",
      "repository_path": "$MUNI_RENOMMAGE_DIR",
      "executable": "munirename-cli",
      "version": "0.3.0",
      "integration_status": "ready",
      "capabilities": ["preview", "apply", "canonical-run"],
      "default_action": "preview",
      "default_parameters": {
        "dry_run": true,
        "confirm_apply": false
      },
      "supports_dry_run": true,
      "destructive_requires_confirmation": true,
      "confirmation_parameter": "confirm_apply",
      "enabled": true
    }
  ]
}
JSON

log_step "Demarrage OrchivisteAPI"
(
  cd "$ORCHIVISTE_API_DIR"
  ORCHIVISTE_API_HOST="$API_HOST" \
  ORCHIVISTE_API_PORT="$API_PORT" \
  ORCHIVISTE_AUTO_MIGRATE=1 \
  ORCHIVISTE_SQLITE_PATH="$SQLITE_PATH" \
  ORCHIVISTE_COCKPIT_CONFIG_FILE="$COCKPIT_CONFIG" \
  ./.build/debug/OrchivisteAPI >"$API_LOG" 2>&1
) &
API_PID=$!

for _ in $(seq 1 60); do
  if ! kill -0 "$API_PID" >/dev/null 2>&1; then
    echo "ECHEC: OrchivisteAPI arretee avant readiness." >&2
    tail -n 120 "$API_LOG" >&2 || true
    exit 1
  fi
  if curl -sS "$BASE_URL/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

METADATA_OUTPUT="$ARTIFACT_DIR/document_metadata.json"
BUNDLE_OUTPUT="$ARTIFACT_DIR/muniregles_bundle.json"
INVALID_METADATA="$ARTIFACT_DIR/document_metadata.invalid.json"
MISSING_BUNDLE="$ARTIFACT_DIR/missing_bundle.json"

log_step "Preparation des artefacts de base (Analyse + Regles)"
ANALYSE_PAYLOAD="$REQUESTS_DIR/00-analyse.payload.json"
ANALYSE_RESPONSE="$RESPONSES_DIR/00-analyse.response.json"
cat > "$ANALYSE_PAYLOAD" <<JSON
{
  "tool_id": "MuniAnalyse",
  "action": "run",
  "parameters": {
    "extract_document_metadata": true,
    "source_paths": [
      "$RESOLUTION_DOC",
      "$AGENDA_DOC"
    ],
    "document_metadata_output_path": "$METADATA_OUTPUT"
  }
}
JSON
ANALYSE_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$ANALYSE_PAYLOAD" "$ANALYSE_RESPONSE")"
assert_http_code "$ANALYSE_CODE" "200" "analyse.run" "$ANALYSE_RESPONSE"
assert_run_response "$ANALYSE_RESPONSE" "MuniAnalyse" "run"
ANALYSE_EXECUTION_ID="$(extract_json_field "$ANALYSE_RESPONSE" "execution_id")"

REGLES_PAYLOAD="$REQUESTS_DIR/00-regles.payload.json"
REGLES_RESPONSE="$RESPONSES_DIR/00-regles.response.json"
cat > "$REGLES_PAYLOAD" <<JSON
{
  "tool_id": "MuniRegles",
  "action": "run",
  "parameters": {
    "operation": "bundle",
    "classification_path": "$CLASSIFICATION_FIXTURE",
    "rules_path": "$RULES_FIXTURE",
    "guide_path": "$GUIDE_FIXTURE",
    "bundle_path": "$BUNDLE_OUTPUT"
  }
}
JSON
REGLES_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$REGLES_PAYLOAD" "$REGLES_RESPONSE")"
assert_http_code "$REGLES_CODE" "200" "regles.run" "$REGLES_RESPONSE"
assert_run_response "$REGLES_RESPONSE" "MuniRegles" "run"
REGLES_EXECUTION_ID="$(extract_json_field "$REGLES_RESPONSE" "execution_id")"

cat > "$INVALID_METADATA" <<'JSON'
{ invalid json
JSON

log_step "Cas negatif A - bundle illisible => fallback explicite"
CASE_A_PAYLOAD="$REQUESTS_DIR/01-case-a.payload.json"
CASE_A_RESPONSE="$RESPONSES_DIR/01-case-a.response.json"
cat > "$CASE_A_PAYLOAD" <<JSON
{
  "tool_id": "MuniRenommage",
  "action": "preview",
  "parameters": {
    "preset_path": "$PRESET_FIXTURE",
    "directory_path": "$SOURCE_DIR",
    "recursive": false,
    "include_hidden": false,
    "dry_run": true,
    "confirm_apply": false,
    "regles_bundle_path": "$MISSING_BUNDLE",
    "regles_naming_rule_id": "rule-demo-simple",
    "regles_apply_rule": true,
    "document_metadata_path": "$METADATA_OUTPUT"
  }
}
JSON
CASE_A_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$CASE_A_PAYLOAD" "$CASE_A_RESPONSE")"
assert_http_code "$CASE_A_CODE" "200" "case-a.bundle-missing" "$CASE_A_RESPONSE"
assert_run_response "$CASE_A_RESPONSE" "MuniRenommage" "preview"
CASE_A_EXECUTION_ID="$(extract_json_field "$CASE_A_RESPONSE" "execution_id")"
CASE_A_RESULT_FILE="$(extract_json_field "$CASE_A_RESPONSE" "result_file")"
assert_fallback_diagnostics "$CASE_A_RESULT_FILE" "case-a"

log_step "Cas negatif B - metadata invalide => fallback explicite"
CASE_B_PAYLOAD="$REQUESTS_DIR/02-case-b.payload.json"
CASE_B_RESPONSE="$RESPONSES_DIR/02-case-b.response.json"
cat > "$CASE_B_PAYLOAD" <<JSON
{
  "tool_id": "MuniRenommage",
  "action": "preview",
  "parameters": {
    "preset_path": "$PRESET_FIXTURE",
    "directory_path": "$SOURCE_DIR",
    "recursive": false,
    "include_hidden": false,
    "dry_run": true,
    "confirm_apply": false,
    "regles_bundle_path": "$BUNDLE_OUTPUT",
    "regles_naming_rule_id": "rule-demo-simple",
    "regles_apply_rule": true,
    "document_metadata_path": "$INVALID_METADATA"
  }
}
JSON
CASE_B_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$CASE_B_PAYLOAD" "$CASE_B_RESPONSE")"
assert_http_code "$CASE_B_CODE" "200" "case-b.metadata-invalid" "$CASE_B_RESPONSE"
assert_run_response "$CASE_B_RESPONSE" "MuniRenommage" "preview"
CASE_B_EXECUTION_ID="$(extract_json_field "$CASE_B_RESPONSE" "execution_id")"
CASE_B_RESULT_FILE="$(extract_json_field "$CASE_B_RESPONSE" "result_file")"
assert_fallback_diagnostics "$CASE_B_RESULT_FILE" "case-b"

log_step "Cas negatif C - regle introuvable => fallback explicite"
CASE_C_PAYLOAD="$REQUESTS_DIR/03-case-c.payload.json"
CASE_C_RESPONSE="$RESPONSES_DIR/03-case-c.response.json"
cat > "$CASE_C_PAYLOAD" <<JSON
{
  "tool_id": "MuniRenommage",
  "action": "preview",
  "parameters": {
    "preset_path": "$PRESET_FIXTURE",
    "directory_path": "$SOURCE_DIR",
    "recursive": false,
    "include_hidden": false,
    "dry_run": true,
    "confirm_apply": false,
    "regles_bundle_path": "$BUNDLE_OUTPUT",
    "regles_naming_rule_id": "rule-missing-negative",
    "regles_apply_rule": true,
    "document_metadata_path": "$METADATA_OUTPUT"
  }
}
JSON
CASE_C_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$CASE_C_PAYLOAD" "$CASE_C_RESPONSE")"
assert_http_code "$CASE_C_CODE" "200" "case-c.rule-missing" "$CASE_C_RESPONSE"
assert_run_response "$CASE_C_RESPONSE" "MuniRenommage" "preview"
CASE_C_EXECUTION_ID="$(extract_json_field "$CASE_C_RESPONSE" "execution_id")"
CASE_C_RESULT_FILE="$(extract_json_field "$CASE_C_RESPONSE" "result_file")"
assert_fallback_diagnostics "$CASE_C_RESULT_FILE" "case-c"

log_step "Cas negatif D - apply sans guard allow_destructive => HTTP 400 explicite"
CASE_D_PAYLOAD="$REQUESTS_DIR/04-case-d.payload.json"
CASE_D_RESPONSE="$RESPONSES_DIR/04-case-d.response.json"
cat > "$CASE_D_PAYLOAD" <<JSON
{
  "tool_id": "MuniRenommage",
  "action": "apply",
  "parameters": {
    "preset_path": "$PRESET_FIXTURE",
    "directory_path": "$SOURCE_DIR",
    "recursive": false,
    "include_hidden": false,
    "dry_run": false,
    "confirm_apply": true,
    "regles_bundle_path": "$BUNDLE_OUTPUT",
    "regles_naming_rule_id": "rule-demo-simple",
    "regles_apply_rule": true,
    "document_metadata_path": "$METADATA_OUTPUT"
  }
}
JSON
CASE_D_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$CASE_D_PAYLOAD" "$CASE_D_RESPONSE")"
assert_http_code "$CASE_D_CODE" "400" "case-d.destructive-guard" "$CASE_D_RESPONSE"
assert_http_400_guard "$CASE_D_RESPONSE"

log_step "Cas negatif E - application impossible => status failed + exit_code non-zero"
CASE_E_PAYLOAD="$REQUESTS_DIR/05-case-e.payload.json"
CASE_E_RESPONSE="$RESPONSES_DIR/05-case-e.response.json"
cat > "$CASE_E_PAYLOAD" <<JSON
{
  "tool_id": "MuniRenommage",
  "action": "preview",
  "parameters": {
    "preset_path": "$PRESET_FIXTURE",
    "directory_path": "$TMP_DIR/nonexistent-source-dir",
    "recursive": false,
    "include_hidden": false,
    "dry_run": true,
    "confirm_apply": false,
    "regles_bundle_path": "$BUNDLE_OUTPUT",
    "regles_naming_rule_id": "rule-demo-simple",
    "regles_apply_rule": true,
    "document_metadata_path": "$METADATA_OUTPUT"
  }
}
JSON
CASE_E_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$CASE_E_PAYLOAD" "$CASE_E_RESPONSE")"
assert_http_code "$CASE_E_CODE" "200" "case-e.unapplicable" "$CASE_E_RESPONSE"
assert_run_response "$CASE_E_RESPONSE" "MuniRenommage" "preview"
CASE_E_EXECUTION_ID="$(extract_json_field "$CASE_E_RESPONSE" "execution_id")"
assert_failure_with_nonzero_exit "$CASE_E_RESPONSE" "case-e"

log_step "Assertions finales (no destructive + historique)"
assert_files_unchanged "$SOURCE_DIR"

HISTORY_RESPONSE="$RESPONSES_DIR/06-history.response.json"
HISTORY_CODE="$(http_json GET "$BASE_URL/v1/cockpit/history?limit=50" "" "$HISTORY_RESPONSE")"
assert_http_code "$HISTORY_CODE" "200" "cockpit.history" "$HISTORY_RESPONSE"
assert_history_contains "$HISTORY_RESPONSE" "$ANALYSE_EXECUTION_ID" "$REGLES_EXECUTION_ID" "$CASE_A_EXECUTION_ID" "$CASE_B_EXECUTION_ID" "$CASE_C_EXECUTION_ID" "$CASE_E_EXECUTION_ID"

echo
echo "Smoke E2E NEGATIF Analyse -> Regles -> Renommage: SUCCES"
echo "Cas verifies:"
echo " - bundle illisible => fallback explicite"
echo " - metadata invalide => fallback explicite"
echo " - regle introuvable => fallback explicite"
echo " - apply sans allow_destructive => HTTP 400 explicite"
echo " - application impossible => status failed + exit_code non-zero"
if [[ "$KEEP_TMP" == "1" ]]; then
  echo "Runtime conserve: $TMP_DIR"
fi
