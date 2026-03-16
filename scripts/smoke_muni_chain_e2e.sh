#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHIVISTE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_SUITE_ROOT="$(cd "$ORCHIVISTE_DIR/.." && pwd)"

MUNI_SUITE_ROOT="${MUNI_SUITE_ROOT:-$DEFAULT_SUITE_ROOT}"
MUNI_ANALYSE_DIR="${MUNI_ANALYSE_DIR:-$MUNI_SUITE_ROOT/MuniAnalyse}"
MUNI_METADONNEES_DIR="${MUNI_METADONNEES_DIR:-$MUNI_SUITE_ROOT/MuniMetadonnees}"
MUNI_PRECLASSEMENT_DIR="${MUNI_PRECLASSEMENT_DIR:-$MUNI_SUITE_ROOT/MuniPreclassement}"
MUNI_CONTROLE_DIR="${MUNI_CONTROLE_DIR:-$MUNI_SUITE_ROOT/MuniControle}"

FIXTURE_PATH="${SMOKE_FIXTURE_PATH:-$ORCHIVISTE_DIR/fixtures/smoke/muni_chain_v1/input_document.txt}"
STRICT="${STRICT:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"
KEEP_TMP="${KEEP_TMP:-0}"
VERBOSE="${VERBOSE:-0}"

log_step() {
  echo
  echo "== $1 =="
}

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

run_tool() {
  local repo_dir="$1"
  local bin_name="$2"
  local request_file="$3"
  local result_file="$4"
  local log_file="$5"

  if ! (cd "$repo_dir" && swift run "$bin_name" run --request "$request_file" --result "$result_file" >"$log_file" 2>&1); then
    echo "ECHEC: execution CLI $bin_name" >&2
    echo "---- CLI LOG ($log_file) ----" >&2
    cat "$log_file" >&2
    return 1
  fi

  if [[ "$VERBOSE" == "1" ]]; then
    echo "---- CLI LOG ($log_file) ----"
    cat "$log_file"
  fi
}

extract_report_uri() {
  local result_file="$1"
  python3 - "$result_file" <<'PY'
import json
import sys

result_path = sys.argv[1]
with open(result_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

artifacts = payload.get("output_artifacts", [])
report_artifacts = [artifact for artifact in artifacts if artifact.get("kind") == "report"]
if not report_artifacts:
    raise SystemExit("No report artifact found")

uri = report_artifacts[0].get("uri", "")
if not uri:
    raise SystemExit("Report artifact URI is empty")

print(uri)
PY
}

assert_result() {
  local result_file="$1"
  local expected_tool="$2"

  python3 - "$result_file" "$expected_tool" "$STRICT" <<'PY'
import json
import sys

result_path, expected_tool, strict = sys.argv[1:4]
with open(result_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

status = payload.get("status")
errors = payload.get("errors") or []
progress = payload.get("progress_events") or []
report_artifacts = [a for a in payload.get("output_artifacts") or [] if a.get("kind") == "report"]

if payload.get("tool") != expected_tool:
    raise SystemExit(f"tool mismatch: expected={expected_tool} actual={payload.get('tool')}")

allowed = {"succeeded", "needs_review"}
if strict == "1":
    allowed = {"succeeded"}
if status not in allowed:
    raise SystemExit(f"unexpected status: {status} (allowed={sorted(allowed)})")

if errors:
    raise SystemExit(f"errors present in result: {errors}")

if not report_artifacts:
    raise SystemExit("missing report artifact in result")

if progress:
    tail_status = progress[-1].get("status")
    if tail_status != status:
        raise SystemExit(f"progress tail status mismatch: tail={tail_status} result={status}")

print(f"OK result {expected_tool}: status={status}")
PY
}

assert_analysis_report() {
  local report_file="$1"
  python3 - "$report_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

required = ["generated_at", "word_count", "sentence_count", "top_terms", "preview"]
for key in required:
    if key not in payload:
        raise SystemExit(f"analysis report missing key: {key}")

if payload["word_count"] <= 0:
    raise SystemExit("analysis report word_count must be > 0")
if not isinstance(payload["top_terms"], list) or not payload["top_terms"]:
    raise SystemExit("analysis report top_terms must be non-empty list")
if not str(payload["preview"]).strip():
    raise SystemExit("analysis report preview must be non-empty")

print("OK analysis report")
PY
}

assert_metadata_report() {
  local report_file="$1"
  python3 - "$report_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

required = ["generated_at", "keyword_count", "keywords", "summary", "suggested_title"]
for key in required:
    if key not in payload:
        raise SystemExit(f"metadata report missing key: {key}")

if payload["keyword_count"] < 1:
    raise SystemExit("metadata report keyword_count must be >= 1")
if not isinstance(payload["keywords"], list) or not payload["keywords"]:
    raise SystemExit("metadata report keywords must be non-empty list")
if not str(payload["summary"]).strip():
    raise SystemExit("metadata report summary must be non-empty")
if not str(payload["suggested_title"]).strip():
    raise SystemExit("metadata report suggested_title must be non-empty")

print("OK metadata report")
PY
}

assert_preclassification_report() {
  local report_file="$1"
  python3 - "$report_file" "$STRICT" <<'PY'
import json
import sys

report_path, strict = sys.argv[1:3]
with open(report_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

required = ["generated_at", "top_score", "confidence_level", "suggestions"]
for key in required:
    if key not in payload:
        raise SystemExit(f"preclassification report missing key: {key}")

if not payload.get("top_class_code"):
    raise SystemExit("preclassification report top_class_code must be non-empty")
if not isinstance(payload["suggestions"], list) or not payload["suggestions"]:
    raise SystemExit("preclassification report suggestions must be non-empty list")
if payload["confidence_level"] not in {"high", "medium", "low"}:
    raise SystemExit(f"invalid confidence_level: {payload['confidence_level']}")

if strict == "1":
    if payload.get("top_class_code") != "INF-300":
        raise SystemExit(f"strict mode: expected top_class_code INF-300, got {payload.get('top_class_code')}")
    if payload.get("confidence_level") != "high":
        raise SystemExit(f"strict mode: expected confidence_level high, got {payload.get('confidence_level')}")

print("OK preclassification report")
PY
}

assert_quality_report() {
  local report_file="$1"
  python3 - "$report_file" "$STRICT" <<'PY'
import json
import sys

report_path, strict = sys.argv[1:3]
with open(report_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

required = ["generated_at", "quality_score", "quality_level", "findings", "gates", "suggested_actions"]
for key in required:
    if key not in payload:
        raise SystemExit(f"quality report missing key: {key}")

score = payload["quality_score"]
if not isinstance(score, int) or score < 0 or score > 100:
    raise SystemExit(f"invalid quality_score: {score}")
if payload["quality_level"] not in {"high", "medium", "low", "critical"}:
    raise SystemExit(f"invalid quality_level: {payload['quality_level']}")
if not isinstance(payload["gates"], list) or not payload["gates"]:
    raise SystemExit("quality report gates must be non-empty list")
if score < 70:
    raise SystemExit(f"quality_score below expected threshold: {score}")

if strict == "1" and score < 90:
    raise SystemExit(f"strict mode: expected quality_score >= 90, got {score}")

print("OK quality report")
PY
}

assert_handoff_integrity() {
  local analyse_result="$1"
  local meta_request="$2"
  local meta_result="$3"
  local pre_request="$4"
  local pre_result="$5"
  local ctrl_request="$6"
  python3 - "$analyse_result" "$meta_request" "$meta_result" "$pre_request" "$pre_result" "$ctrl_request" <<'PY'
import json
import sys

analyse_result, meta_request, meta_result, pre_request, pre_result, ctrl_request = sys.argv[1:7]

with open(analyse_result, "r", encoding="utf-8") as handle:
    ar = json.load(handle)
with open(meta_request, "r", encoding="utf-8") as handle:
    mrq = json.load(handle)
with open(meta_result, "r", encoding="utf-8") as handle:
    mrs = json.load(handle)
with open(pre_request, "r", encoding="utf-8") as handle:
    prq = json.load(handle)
with open(pre_result, "r", encoding="utf-8") as handle:
    prs = json.load(handle)
with open(ctrl_request, "r", encoding="utf-8") as handle:
    crq = json.load(handle)

analysis_uri = ar["output_artifacts"][0]["uri"]
metadata_uri = mrs["output_artifacts"][0]["uri"]
preclass_uri = prs["output_artifacts"][0]["uri"]

meta_input_uri = mrq["input_artifacts"][0]["uri"]
pre_input_uri = prq["input_artifacts"][0]["uri"]
ctrl_input_uris = [item["uri"] for item in crq["input_artifacts"]]

if meta_input_uri != analysis_uri:
    raise SystemExit("handoff mismatch: metadonnees input does not match analyse output")
if pre_input_uri != metadata_uri:
    raise SystemExit("handoff mismatch: preclassement input does not match metadonnees output")
if analysis_uri not in ctrl_input_uris or metadata_uri not in ctrl_input_uris or preclass_uri not in ctrl_input_uris:
    raise SystemExit("handoff mismatch: controle request missing one or more upstream report URIs")

print("OK canonical artifact handoff integrity")
PY
}

need_cmd swift
need_cmd python3

need_dir "$MUNI_ANALYSE_DIR" "MuniAnalyse"
need_dir "$MUNI_METADONNEES_DIR" "MuniMetadonnees"
need_dir "$MUNI_PRECLASSEMENT_DIR" "MuniPreclassement"
need_dir "$MUNI_CONTROLE_DIR" "MuniControle"
need_file "$FIXTURE_PATH" "fixture input document"

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/muni-chain-e2e-XXXXXX")"
OUTPUT_DIR="$RUN_DIR/output"
mkdir -p "$OUTPUT_DIR"

cleanup() {
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$RUN_DIR"
  fi
}
trap cleanup EXIT

log_step "Smoke E2E Muni chain"
echo "STRICT=$STRICT SKIP_BUILD=$SKIP_BUILD"
echo "Suite root: $MUNI_SUITE_ROOT"
echo "Runtime dir: $RUN_DIR"

if [[ "$SKIP_BUILD" != "1" ]]; then
  log_step "Build des 4 outils"
  (cd "$MUNI_ANALYSE_DIR" && swift build)
  (cd "$MUNI_METADONNEES_DIR" && swift build)
  (cd "$MUNI_PRECLASSEMENT_DIR" && swift build)
  (cd "$MUNI_CONTROLE_DIR" && swift build)
fi

ANALYSE_REQ="$RUN_DIR/01-analyse.request.json"
ANALYSE_RES="$OUTPUT_DIR/01-analyse.result.json"
ANALYSE_REP="$OUTPUT_DIR/01-analyse.report.json"
ANALYSE_LOG="$OUTPUT_DIR/01-analyse.cli.log"

cat > "$ANALYSE_REQ" <<JSON
{
  "schema_version": "1.0",
  "request_id": "chain-analyse",
  "tool": "MuniAnalyse",
  "action": "run",
  "parameters": {
    "source_path": "$FIXTURE_PATH",
    "report_path": "$ANALYSE_REP"
  },
  "input_artifacts": []
}
JSON

log_step "Etape 1/4 - MuniAnalyse"
run_tool "$MUNI_ANALYSE_DIR" "muni-analyse-cli" "$ANALYSE_REQ" "$ANALYSE_RES" "$ANALYSE_LOG"
assert_result "$ANALYSE_RES" "MuniAnalyse"
assert_analysis_report "$ANALYSE_REP"
ANALYSE_URI="$(extract_report_uri "$ANALYSE_RES")"
echo "URI analyse: $ANALYSE_URI"

META_REQ="$RUN_DIR/02-metadonnees.request.json"
META_RES="$OUTPUT_DIR/02-metadonnees.result.json"
META_REP="$OUTPUT_DIR/02-metadonnees.report.json"
META_LOG="$OUTPUT_DIR/02-metadonnees.cli.log"

cat > "$META_REQ" <<JSON
{
  "schema_version": "1.0",
  "request_id": "chain-metadonnees",
  "tool": "MuniMetadonnees",
  "action": "run",
  "parameters": {
    "source_path": "$FIXTURE_PATH",
    "metadata_output_path": "$META_REP",
    "max_keywords": 10,
    "summary_sentence_count": 2
  },
  "input_artifacts": [
    {
      "id": "analysis_report",
      "kind": "report",
      "uri": "$ANALYSE_URI",
      "media_type": "application/json",
      "metadata": {}
    }
  ]
}
JSON

log_step "Etape 2/4 - MuniMetadonnees"
run_tool "$MUNI_METADONNEES_DIR" "muni-metadonnees-cli" "$META_REQ" "$META_RES" "$META_LOG"
assert_result "$META_RES" "MuniMetadonnees"
assert_metadata_report "$META_REP"
META_URI="$(extract_report_uri "$META_RES")"
echo "URI metadonnees: $META_URI"

PRE_REQ="$RUN_DIR/03-preclassement.request.json"
PRE_RES="$OUTPUT_DIR/03-preclassement.result.json"
PRE_REP="$OUTPUT_DIR/03-preclassement.report.json"
PRE_LOG="$OUTPUT_DIR/03-preclassement.cli.log"

cat > "$PRE_REQ" <<JSON
{
  "schema_version": "1.0",
  "request_id": "chain-preclassement",
  "tool": "MuniPreclassement",
  "action": "run",
  "parameters": {
    "source_path": "$FIXTURE_PATH",
    "output_report_path": "$PRE_REP",
    "max_suggestions": 3
  },
  "input_artifacts": [
    {
      "id": "metadata_report",
      "kind": "report",
      "uri": "$META_URI",
      "media_type": "application/json",
      "metadata": {}
    }
  ]
}
JSON

log_step "Etape 3/4 - MuniPreclassement"
run_tool "$MUNI_PRECLASSEMENT_DIR" "muni-preclassement-cli" "$PRE_REQ" "$PRE_RES" "$PRE_LOG"
assert_result "$PRE_RES" "MuniPreclassement"
assert_preclassification_report "$PRE_REP"
PRE_URI="$(extract_report_uri "$PRE_RES")"
echo "URI preclassement: $PRE_URI"

CTRL_REQ="$RUN_DIR/04-controle.request.json"
CTRL_RES="$OUTPUT_DIR/04-controle.result.json"
CTRL_REP="$OUTPUT_DIR/04-controle.report.json"
CTRL_LOG="$OUTPUT_DIR/04-controle.cli.log"

cat > "$CTRL_REQ" <<JSON
{
  "schema_version": "1.0",
  "request_id": "chain-controle",
  "tool": "MuniControle",
  "action": "run",
  "parameters": {
    "source_path": "$FIXTURE_PATH",
    "output_report_path": "$CTRL_REP",
    "min_quality_score": 70
  },
  "input_artifacts": [
    {
      "id": "analysis_report",
      "kind": "report",
      "uri": "$ANALYSE_URI",
      "media_type": "application/json",
      "metadata": {}
    },
    {
      "id": "metadata_report",
      "kind": "report",
      "uri": "$META_URI",
      "media_type": "application/json",
      "metadata": {}
    },
    {
      "id": "preclassification_report",
      "kind": "report",
      "uri": "$PRE_URI",
      "media_type": "application/json",
      "metadata": {}
    }
  ]
}
JSON

log_step "Etape 4/4 - MuniControle"
run_tool "$MUNI_CONTROLE_DIR" "muni-controle-cli" "$CTRL_REQ" "$CTRL_RES" "$CTRL_LOG"
assert_result "$CTRL_RES" "MuniControle"
assert_quality_report "$CTRL_REP"

log_step "Assertions finales"
assert_handoff_integrity "$ANALYSE_RES" "$META_REQ" "$META_RES" "$PRE_REQ" "$PRE_RES" "$CTRL_REQ"

echo
echo "Smoke E2E Muni chain: SUCCES"
echo "Resultats:"
echo " - $ANALYSE_RES"
echo " - $META_RES"
echo " - $PRE_RES"
echo " - $CTRL_RES"
if [[ "$KEEP_TMP" == "1" ]]; then
  echo "Runtime conserve: $RUN_DIR"
fi
