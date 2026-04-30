#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_DIR="$ROOT_DIR/OrchivisteAPI"
TMP_DIR_RAW="$(mktemp -d "${TMPDIR:-/tmp}/orchiviste-municonv-resume-XXXXXX")"
TMP_DIR="$(cd "$TMP_DIR_RAW" && pwd -P)"

API_HOST="${ORCHIVISTE_MUNICONV_RESUME_SMOKE_HOST:-127.0.0.1}"
API_PORT="${ORCHIVISTE_MUNICONV_RESUME_SMOKE_PORT:-}"
SKIP_BUILD="${ORCHIVISTE_MUNICONV_RESUME_SMOKE_SKIP_BUILD:-0}"
KEEP_TMP="${ORCHIVISTE_MUNICONV_RESUME_SMOKE_KEEP_TMP:-0}"

API_LOG="$TMP_DIR/orchiviste-api.log"
SQLITE_PATH="$TMP_DIR/orchiviste-smoke.sqlite"
COCKPIT_CONFIG="$TMP_DIR/cockpit.config.json"
STUB_TOOL="$TMP_DIR/municonversion-smoke-cli.py"
INVOCATION_LOG="$TMP_DIR/municonversion-invocations.jsonl"
SOURCE_DIR="$TMP_DIR/source"
DESTINATION_DIR="$TMP_DIR/destination"
RESPONSES_DIR="$TMP_DIR/responses"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Commande requise manquante: $cmd" >&2
    exit 1
  fi
}

pick_port() {
  python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

cleanup() {
  if [[ -n "${API_PID:-}" ]]; then
    kill "$API_PID" >/dev/null 2>&1 || true
    wait "$API_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "Runtime conserve: $TMP_DIR"
  fi
}
trap cleanup EXIT

assert_http_code() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local file="${4:-}"
  if [[ "$actual" != "$expected" ]]; then
    echo "ECHEC [$label] HTTP attendu $expected, recu $actual" >&2
    if [[ -n "$file" && -f "$file" ]]; then
      cat "$file" >&2
    fi
    if [[ -f "$API_LOG" ]]; then
      echo "--- OrchivisteAPI log ---" >&2
      tail -n 120 "$API_LOG" >&2 || true
    fi
    exit 1
  fi
}

assert_file_exists() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "ECHEC [$label] fichier absent: $path" >&2
    exit 1
  fi
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if ! grep -q "$needle" "$file"; then
    echo "ECHEC [$label] contenu absent: $needle" >&2
    cat "$file" >&2
    exit 1
  fi
}

extract_execution_id() {
  local headers="$1"
  python3 - "$headers" <<'PY'
import sys
from urllib.parse import parse_qs, urlparse

headers_path = sys.argv[1]
location = ""
with open(headers_path, "r", encoding="utf-8", errors="replace") as handle:
    for line in handle:
        if line.lower().startswith("location:"):
            location = line.split(":", 1)[1].strip()

query = parse_qs(urlparse(location).query)
execution_id = query.get("execution_id", [""])[0]
if not execution_id:
    raise SystemExit(f"execution_id absent du redirect: {location}")
print(execution_id)
PY
}

assert_result_metadata() {
  local result_file="$1"
  local expected_policy="$2"
  local expected_converted="$3"
  local expected_skipped="$4"
  local label="$5"
  python3 - "$result_file" "$expected_policy" "$expected_converted" "$expected_skipped" "$SOURCE_DIR" "$DESTINATION_DIR" "$label" <<'PY'
import json
import sys
from pathlib import Path

result_file, expected_policy, expected_converted, expected_skipped, source_dir, destination_dir, label = sys.argv[1:8]
with open(result_file, "r", encoding="utf-8") as handle:
    result = json.load(handle)

metadata = result.get("metadata", {})
checks = {
    "status": result.get("status"),
    "tool": result.get("tool"),
    "profile_id": metadata.get("profile_id"),
    "collision_policy": metadata.get("collision_policy"),
    "converted": metadata.get("converted"),
    "skipped_existing": metadata.get("skipped_existing"),
    "dry_run": metadata.get("dry_run"),
}
expected = {
    "status": "succeeded",
    "tool": "MuniConversion",
    "profile_id": "txt_to_pdf",
    "collision_policy": expected_policy,
    "converted": int(expected_converted),
    "skipped_existing": int(expected_skipped),
    "dry_run": False,
}
for key, expected_value in expected.items():
    if checks.get(key) != expected_value:
        raise SystemExit(f"ECHEC [{label}] {key}: attendu {expected_value!r}, recu {checks.get(key)!r}")

path_checks = {
    "source_path": (metadata.get("source_path"), source_dir),
    "output_root_path": (metadata.get("output_root_path"), destination_dir),
}
for key, (actual_path, expected_path) in path_checks.items():
    if actual_path is None or Path(actual_path).resolve() != Path(expected_path).resolve():
        raise SystemExit(f"ECHEC [{label}] {key}: attendu {expected_path!r}, recu {actual_path!r}")
print(f"OK  {label}: policy={expected_policy}, converted={expected_converted}, skipped={expected_skipped}")
PY
}

assert_invocations_are_canonical() {
  python3 - "$INVOCATION_LOG" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    invocations = [json.loads(line) for line in handle if line.strip()]

if len(invocations) != 2:
    raise SystemExit(f"ECHEC [canonical] 2 invocations attendues, recu {len(invocations)}")

for index, invocation in enumerate(invocations, start=1):
    args = invocation.get("args", [])
    if len(args) != 5 or args[0] != "run" or args[1] != "--request" or args[3] != "--result":
        raise SystemExit(f"ECHEC [canonical] invocation {index} invalide: {args}")
print("OK  contrat canonique run --request --result verifie")
PY
}

need_cmd curl
need_cmd python3
if [[ "$SKIP_BUILD" != "1" ]]; then
  need_cmd swift
fi

if [[ -z "$API_PORT" ]]; then
  API_PORT="$(pick_port)"
fi
BASE_URL="http://${API_HOST}:${API_PORT}"

mkdir -p "$SOURCE_DIR" "$DESTINATION_DIR" "$RESPONSES_DIR"
printf "Document source smoke S6.7\n" > "$SOURCE_DIR/note.txt"
printf "PDF existant avant reprise\n" > "$DESTINATION_DIR/note.pdf"

cat > "$STUB_TOOL" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

args = sys.argv[1:]
invocation_log = os.environ.get("SMOKE_MUNICONVERSION_INVOCATIONS")
if invocation_log:
    with open(invocation_log, "a", encoding="utf-8") as handle:
        handle.write(json.dumps({"args": args}, ensure_ascii=False) + "\n")

if len(args) != 5 or args[0] != "run" or args[1] != "--request" or args[3] != "--result":
    print("invalid args", file=sys.stderr)
    sys.exit(2)

request_path = Path(args[2])
result_path = Path(args[4])

with request_path.open("r", encoding="utf-8") as handle:
    request = json.load(handle)

parameters = request.get("parameters", {})
source_dir = Path(parameters["source_path"])
output_dir = Path(parameters.get("output_path") or parameters["source_path"])
profile_id = parameters.get("profile_id", "txt_to_pdf")
collision_policy = parameters.get("collision_policy", "skip_existing")
dry_run = bool(parameters.get("dry_run", True))
confirm_convert = bool(parameters.get("confirm_convert", False))
action = request.get("action", "convert")

if action == "convert" and not dry_run and not confirm_convert:
    print("confirm_convert=true requis", file=sys.stderr)
    sys.exit(3)

output_dir.mkdir(parents=True, exist_ok=True)
sources = sorted(path for path in source_dir.iterdir() if path.is_file() and path.suffix.lower() == ".txt")

converted = 0
skipped = 0
errors = 0
for source in sources:
    target = output_dir / f"{source.stem}.pdf"
    if dry_run:
        continue
    if target.exists() and collision_policy == "skip_existing":
        skipped += 1
        continue
    if target.exists() and collision_policy == "rename_with_suffix":
        suffix = 1
        while True:
            candidate = output_dir / f"{source.stem} ({suffix}).pdf"
            if not candidate.exists():
                target = candidate
                break
            suffix += 1
    target.write_text(f"PDF smoke generated from {source.name}\n", encoding="utf-8")
    converted += 1

now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
summary = (
    f"Conversion terminee: {converted} converti(s), "
    f"{skipped} ignore(s) car existant(s), {errors} erreur(s)."
)
result = {
    "schema_version": request.get("schema_version", "1.0"),
    "request_id": request["request_id"],
    "tool": "MuniConversion",
    "status": "succeeded",
    "started_at": now,
    "finished_at": now,
    "progress_events": [
        {
            "request_id": request["request_id"],
            "status": "running",
            "stage": "accepted",
            "percent": 0,
            "message": "Request accepted.",
            "occurred_at": now,
            "metadata": {}
        },
        {
            "request_id": request["request_id"],
            "status": "succeeded",
            "stage": "completed",
            "percent": 100,
            "message": summary,
            "occurred_at": now,
            "metadata": {}
        }
    ],
    "output_artifacts": [
        {
            "id": "output_root",
            "kind": "output",
            "uri": output_dir.resolve().as_uri() + "/",
            "media_type": "inode/directory",
            "metadata": {}
        }
    ],
    "errors": [],
    "summary": summary,
    "metadata": {
        "action": action,
        "source_path": str(source_dir),
        "output_root_path": str(output_dir),
        "profile_id": profile_id,
        "include_subdirectories": bool(parameters.get("include_subdirectories", False)),
        "ignore_hidden_files": bool(parameters.get("ignore_hidden_files", True)),
        "dry_run": dry_run,
        "collision_policy": collision_policy,
        "total_scanned": len(sources),
        "total_matched": len(sources),
        "converted": converted,
        "simulated": len(sources) if dry_run else 0,
        "ignored": 0,
        "skipped_existing": skipped,
        "errors": errors
    }
}

with result_path.open("w", encoding="utf-8") as handle:
    json.dump(result, handle, indent=2, ensure_ascii=False)
PY
chmod +x "$STUB_TOOL"

cat > "$COCKPIT_CONFIG" <<JSON
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
      "id": "MuniConversion",
      "display_name": "MuniConversion",
      "mission": "Smoke cible reprise employe MuniConversion.",
      "executable": "municonversion-smoke-cli",
      "executable_path": "$STUB_TOOL",
      "version": "0.0.1",
      "integration_status": "ready",
      "capabilities": ["analyze", "convert", "canonical-run"],
      "default_action": "analyze",
      "default_parameters": {
        "dry_run": true,
        "confirm_convert": false,
        "include_subdirectories": false,
        "ignore_hidden_files": true,
        "preserve_relative_structure": false,
        "collision_policy": "skip_existing"
      },
      "supports_dry_run": true,
      "destructive_requires_confirmation": true,
      "confirmation_parameter": "confirm_convert",
      "enabled": true
    }
  ]
}
JSON

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "== Build OrchivisteAPI =="
  (cd "$API_DIR" && swift build -c debug --product OrchivisteAPI)
fi

echo "== Demarrage OrchivisteAPI =="
(
  cd "$API_DIR"
  ORCHIVISTE_API_HOST="$API_HOST" \
  ORCHIVISTE_API_PORT="$API_PORT" \
  ORCHIVISTE_AUTO_MIGRATE=1 \
  ORCHIVISTE_SQLITE_PATH="$SQLITE_PATH" \
  ORCHIVISTE_COCKPIT_CONFIG_FILE="$COCKPIT_CONFIG" \
  SMOKE_MUNICONVERSION_INVOCATIONS="$INVOCATION_LOG" \
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

echo "== Scenario S6.7: skip_existing puis reprise employee rename_with_suffix =="
FIRST_HEADERS="$RESPONSES_DIR/01-first.headers"
FIRST_BODY="$RESPONSES_DIR/01-first.html"
FIRST_CODE="$(curl -sS -D "$FIRST_HEADERS" -o "$FIRST_BODY" -w "%{http_code}" \
  --data-urlencode "source_directory=$SOURCE_DIR" \
  --data-urlencode "destination_directory=$DESTINATION_DIR" \
  --data-urlencode "use_separate_destination=on" \
  --data-urlencode "profile_id=txt_to_pdf" \
  --data-urlencode "collision_policy=skip_existing" \
  --data-urlencode "operation=convert" \
  "$BASE_URL/ui/muni/apps/MuniConversion/employe/run")"
assert_http_code "$FIRST_CODE" "303" "employee.run.skip_existing" "$FIRST_BODY"
FIRST_EXECUTION_ID="$(extract_execution_id "$FIRST_HEADERS")"

FIRST_RESULT="$RESPONSES_DIR/02-first-result.json"
FIRST_RESULT_CODE="$(curl -sS -o "$FIRST_RESULT" -w "%{http_code}" "$BASE_URL/ui/muni/apps/MuniConversion/employe/result/$FIRST_EXECUTION_ID")"
assert_http_code "$FIRST_RESULT_CODE" "200" "employee.result.first" "$FIRST_RESULT"
assert_result_metadata "$FIRST_RESULT" "skip_existing" "0" "1" "premier run skip_existing"

FIRST_PAGE="$RESPONSES_DIR/03-first-page.html"
FIRST_PAGE_CODE="$(curl -sS -o "$FIRST_PAGE" -w "%{http_code}" "$BASE_URL/ui/muni/apps/MuniConversion/employe?execution_id=$FIRST_EXECUTION_ID&resume_execution_id=$FIRST_EXECUTION_ID")"
assert_http_code "$FIRST_PAGE_CODE" "200" "employee.resume.page" "$FIRST_PAGE"
assert_contains "$FIRST_PAGE" "Reprendre ce lot" "employee.resume.page"
assert_contains "$FIRST_PAGE" "/ui/muni/apps/MuniConversion/employe/resume" "employee.resume.form"

RESUME_HEADERS="$RESPONSES_DIR/04-resume.headers"
RESUME_BODY="$RESPONSES_DIR/04-resume.html"
RESUME_CODE="$(curl -sS -D "$RESUME_HEADERS" -o "$RESUME_BODY" -w "%{http_code}" \
  --data-urlencode "execution_id=$FIRST_EXECUTION_ID" \
  --data-urlencode "destination_directory=$DESTINATION_DIR" \
  --data-urlencode "use_separate_destination=on" \
  --data-urlencode "collision_policy=rename_with_suffix" \
  "$BASE_URL/ui/muni/apps/MuniConversion/employe/resume")"
assert_http_code "$RESUME_CODE" "303" "employee.resume.rename_with_suffix" "$RESUME_BODY"
RESUME_EXECUTION_ID="$(extract_execution_id "$RESUME_HEADERS")"

RESUME_RESULT="$RESPONSES_DIR/05-resume-result.json"
RESUME_RESULT_CODE="$(curl -sS -o "$RESUME_RESULT" -w "%{http_code}" "$BASE_URL/ui/muni/apps/MuniConversion/employe/result/$RESUME_EXECUTION_ID")"
assert_http_code "$RESUME_RESULT_CODE" "200" "employee.result.resume" "$RESUME_RESULT"
assert_result_metadata "$RESUME_RESULT" "rename_with_suffix" "1" "0" "reprise rename_with_suffix"

assert_file_exists "$DESTINATION_DIR/note.pdf" "sortie initiale occupee"
assert_file_exists "$DESTINATION_DIR/note (1).pdf" "sortie reprise suffixee"
PDF_COUNT="$(find "$DESTINATION_DIR" -maxdepth 1 -type f -name "*.pdf" | wc -l | tr -d " ")"
if [[ "$PDF_COUNT" != "2" ]]; then
  echo "ECHEC [sorties] 2 PDF attendus, recu $PDF_COUNT" >&2
  find "$DESTINATION_DIR" -maxdepth 1 -type f -print >&2
  exit 1
fi

assert_invocations_are_canonical

echo
echo "Smoke reprise employee MuniConversion: SUCCES"
echo " - premier run: $FIRST_EXECUTION_ID (skip_existing, skipped_existing=1)"
echo " - reprise: $RESUME_EXECUTION_ID (rename_with_suffix, converted=1)"
echo " - sorties: $DESTINATION_DIR/note.pdf ; $DESTINATION_DIR/note (1).pdf"
