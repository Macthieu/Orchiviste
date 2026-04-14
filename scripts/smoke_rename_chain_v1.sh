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
STRICT="${STRICT:-0}"
API_PORT="${ORCHIVISTE_SMOKE_RENAME_PORT:-}"
API_HOST="${ORCHIVISTE_SMOKE_RENAME_HOST:-127.0.0.1}"

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

assert_run_response() {
  local response_file="$1"
  local expected_tool="$2"
  local expected_action="$3"
  python3 - "$response_file" "$expected_tool" "$expected_action" "$STRICT" <<'PY'
import json
import os
import sys
import unicodedata
import unicodedata

response_file, expected_tool, expected_action, strict = sys.argv[1:5]
with open(response_file, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

status = payload.get("status")
allowed = {"succeeded", "needs_review"}
if strict == "1":
    allowed = {"succeeded"}
if status not in allowed:
    raise SystemExit(f"unexpected run status={status} expected one of {sorted(allowed)}")

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

errors = payload.get("errors") or []
if errors:
    raise SystemExit(f"errors present in run response: {errors}")
PY
}

assert_analyse_result() {
  local result_file="$1"
  local metadata_output_path="$2"
  python3 - "$result_file" "$metadata_output_path" "$STRICT" <<'PY'
import json
import os
import sys

result_file, metadata_output_path, strict = sys.argv[1:4]
with open(result_file, "r", encoding="utf-8") as handle:
    result = json.load(handle)

status = result.get("status")
allowed = {"succeeded", "needs_review"}
if strict == "1":
    allowed = {"succeeded"}
if status not in allowed:
    raise SystemExit(f"unexpected analyse status: {status}")

artifacts = result.get("output_artifacts") or []
metadata_artifacts = [a for a in artifacts if a.get("id") == "document_metadata" and a.get("kind") == "metadata"]
if not metadata_artifacts:
    raise SystemExit("document_metadata artifact missing")

if not os.path.exists(metadata_output_path):
    raise SystemExit(f"metadata output missing: {metadata_output_path}")

with open(metadata_output_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

documents = payload.get("documents") or []
if len(documents) < 2:
    raise SystemExit(f"expected at least 2 extracted documents, got {len(documents)}")
for document in documents:
    for key in ("source_file", "document_type", "document_subject", "document_date"):
        value = (document.get(key) or "").strip()
        if not value:
            raise SystemExit(f"document missing key {key}: {document}")
PY
}

assert_regles_result() {
  local result_file="$1"
  local bundle_path="$2"
  local rule_id="$3"
  python3 - "$result_file" "$bundle_path" "$rule_id" "$STRICT" <<'PY'
import json
import os
import sys

result_file, bundle_path, rule_id, strict = sys.argv[1:5]
with open(result_file, "r", encoding="utf-8") as handle:
    result = json.load(handle)

status = result.get("status")
allowed = {"succeeded", "needs_review"}
if strict == "1":
    allowed = {"succeeded"}
if status not in allowed:
    raise SystemExit(f"unexpected regles status: {status}")

if not os.path.exists(bundle_path):
    raise SystemExit(f"bundle missing: {bundle_path}")

with open(bundle_path, "r", encoding="utf-8") as handle:
    bundle = json.load(handle)

contracts = bundle.get("naming_rule_contracts") or []
contract = next((c for c in contracts if c.get("rule_id") == rule_id), None)
if contract is None:
    raise SystemExit(f"naming_rule_contract not found for {rule_id}")
required = sorted(contract.get("required_metadata_fields") or [])
expected = sorted(["document_type", "document_subject", "document_date"])
if required != expected:
    raise SystemExit(f"required_metadata_fields mismatch for {rule_id}: got={required} expected={expected}")
PY
}

assert_preview_result() {
  local result_file="$1"
  local expected_rule="$2"
  python3 - "$result_file" "$expected_rule" "$STRICT" <<'PY'
import json
import sys

result_file, expected_rule, strict = sys.argv[1:4]
with open(result_file, "r", encoding="utf-8") as handle:
    result = json.load(handle)

status = result.get("status")
allowed = {"succeeded", "needs_review"}
if strict == "1":
    allowed = {"succeeded"}
if status not in allowed:
    raise SystemExit(f"unexpected preview status: {status}")

metadata = result.get("metadata") or {}
if metadata.get("regles_source") != "muniregles_bundle":
    raise SystemExit(f"preview regles_source mismatch: {metadata.get('regles_source')}")
if metadata.get("regles_rule_id") != expected_rule:
    raise SystemExit(f"preview regles_rule_id mismatch: {metadata.get('regles_rule_id')}")
if not str(metadata.get("regles_bundle_version", "")).strip():
    raise SystemExit("preview regles_bundle_version missing")
if not str(metadata.get("regles_module_version", "")).strip():
    raise SystemExit("preview regles_module_version missing")

plan_digest = str(metadata.get("plan_digest", "")).strip()
if not plan_digest:
    raise SystemExit("preview plan_digest missing")
PY
}

assert_apply_result() {
  local result_file="$1"
  local expected_rule="$2"
  local expected_plan_digest="$3"
  python3 - "$result_file" "$expected_rule" "$expected_plan_digest" "$STRICT" <<'PY'
import json
import sys

result_file, expected_rule, expected_plan_digest, strict = sys.argv[1:5]
with open(result_file, "r", encoding="utf-8") as handle:
    result = json.load(handle)

status = result.get("status")
allowed = {"succeeded"}
if strict != "1":
    allowed = {"succeeded", "needs_review"}
if status not in allowed:
    raise SystemExit(f"unexpected apply status: {status}")

metadata = result.get("metadata") or {}
if metadata.get("regles_source") != "muniregles_bundle":
    raise SystemExit(f"apply regles_source mismatch: {metadata.get('regles_source')}")
if metadata.get("regles_rule_id") != expected_rule:
    raise SystemExit(f"apply regles_rule_id mismatch: {metadata.get('regles_rule_id')}")

plan_digest = str(metadata.get("plan_digest", "")).strip()
if not plan_digest:
    raise SystemExit("apply plan_digest missing")
if plan_digest != expected_plan_digest:
    raise SystemExit(f"apply plan_digest mismatch: {plan_digest} != {expected_plan_digest}")
PY
}

assert_final_names() {
  local metadata_output_path="$1"
  local source_dir="$2"
  python3 - "$metadata_output_path" "$source_dir" <<'PY'
import json
import os
import sys
import unicodedata

metadata_output_path, source_dir = sys.argv[1:3]
with open(metadata_output_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

documents = payload.get("documents") or []
if not documents:
    raise SystemExit("no documents in metadata payload")

expected = []
for doc in documents:
    source_file = os.path.basename((doc.get("source_file") or "").strip())
    ext = os.path.splitext(source_file)[1]
    if ext.startswith("."):
        ext = ext[1:]
    base = f"{doc.get('document_type', '').strip()} – {doc.get('document_subject', '').strip()} – {doc.get('document_date', '').strip()}"
    if not base.strip(" –"):
        raise SystemExit(f"invalid expected base name from metadata: {doc}")
    expected.append(f"{base}.{ext}" if ext else base)

expected = sorted(expected)
actual = sorted([
    name for name in os.listdir(source_dir)
    if os.path.isfile(os.path.join(source_dir, name))
])

expected_nfc = sorted(unicodedata.normalize("NFC", name) for name in expected)
actual_nfc = sorted(unicodedata.normalize("NFC", name) for name in actual)

if actual_nfc != expected_nfc:
    raise SystemExit(
        "final names mismatch\n"
        f"expected={expected}\n"
        f"actual={actual}\n"
        f"expected_nfc={expected_nfc}\n"
        f"actual_nfc={actual_nfc}"
    )

print("OK final names:", ", ".join(actual))
PY
}

assert_history_and_pilotage() {
  local history_file="$1"
  local historique_html="$2"
  local analyse_execution="$3"
  local regles_execution="$4"
  local preview_execution="$5"
  local apply_execution="$6"
  python3 - "$history_file" "$analyse_execution" "$regles_execution" "$preview_execution" "$apply_execution" <<'PY'
import json
import sys

history_file, analyse_execution, regles_execution, preview_execution, apply_execution = sys.argv[1:6]
with open(history_file, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

entries = payload.get("entries") or []
if len(entries) < 4:
    raise SystemExit(f"history has too few entries: {len(entries)}")

by_exec = {entry.get("execution_id"): entry for entry in entries}
required = [analyse_execution, regles_execution, preview_execution, apply_execution]
for execution_id in required:
    if execution_id not in by_exec:
        raise SystemExit(f"execution id missing from history: {execution_id}")

if by_exec[analyse_execution].get("tool_id") != "MuniAnalyse":
    raise SystemExit("history mismatch for analyse tool_id")
if by_exec[regles_execution].get("tool_id") != "MuniRegles":
    raise SystemExit("history mismatch for regles tool_id")
if by_exec[preview_execution].get("tool_id") != "MuniRenommage":
    raise SystemExit("history mismatch for preview tool_id")
if by_exec[apply_execution].get("tool_id") != "MuniRenommage":
    raise SystemExit("history mismatch for apply tool_id")
PY

  for execution_id in "$analyse_execution" "$regles_execution" "$preview_execution" "$apply_execution"; do
    if ! grep -q "$execution_id" "$historique_html"; then
      echo "ECHEC: execution id absente de /ui/pilotage/historique: $execution_id" >&2
      exit 1
    fi
  done
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

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orchiviste-rename-chain-v1-XXXXXX")"
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

log_step "Preparation des sources demo (fixtures regression analyse)"
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
if not resolution_text.strip():
    raise SystemExit("resolution fixture text is empty")
if not agenda_text.strip():
    raise SystemExit("agenda fixture text is empty")

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
      "mission": "Extraction metadata deterministe pour smoke rename chain.",
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
      "mission": "Bundle de regles documentaire pour smoke rename chain.",
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
      "mission": "Renommage canonique base sur bundle et metadata.",
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

log_step "Demarrage OrchivisteAPI (pilotage local)"
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
    echo "ECHEC: OrchivisteAPI arrete avant readiness." >&2
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
VALIDATION_REPORT_OUTPUT="$ARTIFACT_DIR/muniregles_validation_report.json"

log_step "Etape 1/4 - MuniAnalyse (metadata)"
ANALYSE_PAYLOAD="$REQUESTS_DIR/01-analyse.payload.json"
ANALYSE_RESPONSE="$RESPONSES_DIR/01-analyse.response.json"
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
ANALYSE_RESULT_FILE="$(extract_json_field "$ANALYSE_RESPONSE" "result_file")"
assert_analyse_result "$ANALYSE_RESULT_FILE" "$METADATA_OUTPUT"

log_step "Etape 2/4 - MuniRegles (bundle)"
REGLES_PAYLOAD="$REQUESTS_DIR/02-regles.payload.json"
REGLES_RESPONSE="$RESPONSES_DIR/02-regles.response.json"
cat > "$REGLES_PAYLOAD" <<JSON
{
  "tool_id": "MuniRegles",
  "action": "run",
  "parameters": {
    "operation": "bundle",
    "classification_path": "$CLASSIFICATION_FIXTURE",
    "rules_path": "$RULES_FIXTURE",
    "guide_path": "$GUIDE_FIXTURE",
    "bundle_path": "$BUNDLE_OUTPUT",
    "report_path": "$VALIDATION_REPORT_OUTPUT"
  }
}
JSON

REGLES_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$REGLES_PAYLOAD" "$REGLES_RESPONSE")"
assert_http_code "$REGLES_CODE" "200" "regles.run" "$REGLES_RESPONSE"
assert_run_response "$REGLES_RESPONSE" "MuniRegles" "run"

REGLES_EXECUTION_ID="$(extract_json_field "$REGLES_RESPONSE" "execution_id")"
REGLES_RESULT_FILE="$(extract_json_field "$REGLES_RESPONSE" "result_file")"
assert_regles_result "$REGLES_RESULT_FILE" "$BUNDLE_OUTPUT" "rule-demo-simple"

log_step "Etape 3/4 - MuniRenommage preview"
PREVIEW_PAYLOAD="$REQUESTS_DIR/03-renommage-preview.payload.json"
PREVIEW_RESPONSE="$RESPONSES_DIR/03-renommage-preview.response.json"
cat > "$PREVIEW_PAYLOAD" <<JSON
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
    "document_metadata_path": "$METADATA_OUTPUT"
  }
}
JSON

PREVIEW_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$PREVIEW_PAYLOAD" "$PREVIEW_RESPONSE")"
assert_http_code "$PREVIEW_CODE" "200" "renommage.preview" "$PREVIEW_RESPONSE"
assert_run_response "$PREVIEW_RESPONSE" "MuniRenommage" "preview"

PREVIEW_EXECUTION_ID="$(extract_json_field "$PREVIEW_RESPONSE" "execution_id")"
PREVIEW_RESULT_FILE="$(extract_json_field "$PREVIEW_RESPONSE" "result_file")"
assert_preview_result "$PREVIEW_RESULT_FILE" "rule-demo-simple"
PREVIEW_PLAN_DIGEST="$(extract_json_field "$PREVIEW_RESULT_FILE" "metadata.plan_digest")"

log_step "Etape 4/4 - MuniRenommage apply controle"
APPLY_PAYLOAD="$REQUESTS_DIR/04-renommage-apply.payload.json"
APPLY_RESPONSE="$RESPONSES_DIR/04-renommage-apply.response.json"
cat > "$APPLY_PAYLOAD" <<JSON
{
  "tool_id": "MuniRenommage",
  "action": "apply",
  "allow_destructive": true,
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
    "document_metadata_path": "$METADATA_OUTPUT",
    "expected_plan_digest": "$PREVIEW_PLAN_DIGEST"
  }
}
JSON

APPLY_CODE="$(http_json POST "$BASE_URL/v1/cockpit/runs" "$APPLY_PAYLOAD" "$APPLY_RESPONSE")"
assert_http_code "$APPLY_CODE" "200" "renommage.apply" "$APPLY_RESPONSE"
assert_run_response "$APPLY_RESPONSE" "MuniRenommage" "apply"

APPLY_EXECUTION_ID="$(extract_json_field "$APPLY_RESPONSE" "execution_id")"
APPLY_RESULT_FILE="$(extract_json_field "$APPLY_RESPONSE" "result_file")"
assert_apply_result "$APPLY_RESULT_FILE" "rule-demo-simple" "$PREVIEW_PLAN_DIGEST"

log_step "Assertions finales (noms + historique/pilotage)"
assert_final_names "$METADATA_OUTPUT" "$SOURCE_DIR"

HISTORY_RESPONSE="$RESPONSES_DIR/05-history.response.json"
HISTORY_CODE="$(http_json GET "$BASE_URL/v1/cockpit/history?limit=20" "" "$HISTORY_RESPONSE")"
assert_http_code "$HISTORY_CODE" "200" "cockpit.history" "$HISTORY_RESPONSE"

HISTORIQUE_HTML="$RESPONSES_DIR/06-ui-pilotage-historique.html"
HISTORIQUE_CODE="$(curl -sS -o "$HISTORIQUE_HTML" -w "%{http_code}" "$BASE_URL/ui/pilotage/historique")"
assert_http_code "$HISTORIQUE_CODE" "200" "ui.pilotage.historique" "$HISTORIQUE_HTML"

assert_history_and_pilotage \
  "$HISTORY_RESPONSE" \
  "$HISTORIQUE_HTML" \
  "$ANALYSE_EXECUTION_ID" \
  "$REGLES_EXECUTION_ID" \
  "$PREVIEW_EXECUTION_ID" \
  "$APPLY_EXECUTION_ID"

echo
echo "Smoke E2E Analyse -> Regles -> Renommage: SUCCES"
echo "Execution IDs:"
echo " - analyse: $ANALYSE_EXECUTION_ID"
echo " - regles: $REGLES_EXECUTION_ID"
echo " - preview: $PREVIEW_EXECUTION_ID"
echo " - apply: $APPLY_EXECUTION_ID"
echo "Artifacts:"
echo " - metadata: $METADATA_OUTPUT"
echo " - bundle: $BUNDLE_OUTPUT"
echo " - history response: $HISTORY_RESPONSE"
if [[ "$KEEP_TMP" == "1" ]]; then
  echo "Runtime conserve: $TMP_DIR"
fi
