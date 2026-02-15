#!/usr/bin/env bash
set -euo pipefail

API_BASE="${ORCHIVISTE_API_BASE:-http://127.0.0.1:28780}"
TIMEOUT_SECONDS="${ORCHIVISTE_SMOKE_TIMEOUT:-45}"
REVIEW_CLASS_CODE="${ORCHIVISTE_REVIEW_CLASS_CODE:-ADM-PV}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

json_get() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import sys

file_path = sys.argv[1]
path = sys.argv[2]

with open(file_path, "r", encoding="utf-8") as f:
    data = json.load(f)

current = data
for part in path.split("."):
    if isinstance(current, list):
        if not part.isdigit():
            current = None
            break
        idx = int(part)
        if idx < 0 or idx >= len(current):
            current = None
            break
        current = current[idx]
        continue
    if isinstance(current, dict):
        current = current.get(part)
        continue
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

json_len() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import sys

file_path = sys.argv[1]
path = sys.argv[2]
with open(file_path, "r", encoding="utf-8") as f:
    data = json.load(f)

current = data
for part in path.split("."):
    if isinstance(current, list):
        if not part.isdigit():
            current = []
            break
        idx = int(part)
        if idx < 0 or idx >= len(current):
            current = []
            break
        current = current[idx]
        continue
    if isinstance(current, dict):
        current = current.get(part, [])
        continue
    current = []
    break

if isinstance(current, list):
    print(len(current))
else:
    print(0)
PY
}

http_json() {
  local method="$1"
  local url="$2"
  local body_file="$3"
  local out_file="$4"
  shift 4
  local headers=("$@")
  local code

  if [[ -n "$body_file" ]]; then
    if (( ${#headers[@]} > 0 )); then
      code="$(curl -sS -o "$out_file" -w "%{http_code}" -X "$method" "$url" \
        -H "Content-Type: application/json" \
        "${headers[@]}" \
        --data-binary "@$body_file")"
    else
      code="$(curl -sS -o "$out_file" -w "%{http_code}" -X "$method" "$url" \
        -H "Content-Type: application/json" \
        --data-binary "@$body_file")"
    fi
  else
    if (( ${#headers[@]} > 0 )); then
      code="$(curl -sS -o "$out_file" -w "%{http_code}" -X "$method" "$url" \
        "${headers[@]}")"
    else
      code="$(curl -sS -o "$out_file" -w "%{http_code}" -X "$method" "$url")"
    fi
  fi
  echo "$code"
}

http_raw() {
  local method="$1"
  local url="$2"
  local out_file="$3"
  local code
  code="$(curl -sS -o "$out_file" -w "%{http_code}" -X "$method" "$url")"
  echo "$code"
}

assert_code() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local body_file="$4"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL [$label] expected HTTP $expected, got $actual" >&2
    if [[ -f "$body_file" ]]; then
      cat "$body_file" >&2
    fi
    exit 1
  fi
}

need_cmd curl
need_cmd python3

echo "== Orchiviste MVP smoke test =="
echo "API: $API_BASE"

health_file="$TMP_DIR/health.json"
health_code="$(http_raw GET "$API_BASE/v1/health" "$health_file")"
assert_code "$health_code" "200" "health" "$health_file"
echo "OK  health"

ingest_payload="$TMP_DIR/ingest.json"
idem_key="smoke-$(date +%s)"
cat >"$ingest_payload" <<JSON
{
  "fileURL": "smoke-proces-verbal.pdf",
  "source": { "kind": "local" },
  "tags": ["smoke", "mvp"]
}
JSON

ingest_file="$TMP_DIR/ingest_response.json"
ingest_code="$(http_json POST "$API_BASE/v1/ingest" "$ingest_payload" "$ingest_file" -H "Idempotency-Key: $idem_key")"
assert_code "$ingest_code" "202" "ingest" "$ingest_file"
job_id="$(json_get "$ingest_file" "taskId")"
if [[ -z "$job_id" ]]; then
  echo "FAIL [ingest] missing taskId in response" >&2
  cat "$ingest_file" >&2
  exit 1
fi
echo "OK  ingest (job_id=$job_id)"

job_file="$TMP_DIR/job.json"
job_status=""
deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  job_code="$(http_raw GET "$API_BASE/v1/jobs/$job_id" "$job_file")"
  if [[ "$job_code" == "200" ]]; then
    job_status="$(json_get "$job_file" "status")"
    if [[ "$job_status" == "needs_review" || "$job_status" == "completed" || "$job_status" == "failed" || "$job_status" == "cancelled" ]]; then
      break
    fi
  fi
  sleep 1
done

if [[ -z "$job_status" ]]; then
  echo "FAIL [jobs] unable to resolve job status before timeout" >&2
  cat "$job_file" >&2
  exit 1
fi
echo "OK  job status reached: $job_status"

thumbnail_file="$TMP_DIR/thumbnail.jpg"
thumbnail_code=""
deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  thumbnail_code="$(http_raw GET "$API_BASE/v1/preview/$job_id/thumbnail" "$thumbnail_file")"
  if [[ "$thumbnail_code" == "200" ]]; then
    break
  fi
  sleep 1
done
assert_code "$thumbnail_code" "200" "preview.thumbnail" "$thumbnail_file"
echo "OK  preview thumbnail"

page_file="$TMP_DIR/page1.jpg"
page_code="$(http_raw GET "$API_BASE/v1/preview/$job_id/page/1.jpg" "$page_file")"
if [[ "$page_code" == "200" ]]; then
  echo "OK  preview page 1 (.jpg)"
elif [[ "$page_code" == "400" ]]; then
  # Backward-compatible fallback for older route parsing.
  page_code="$(http_raw GET "$API_BASE/v1/preview/$job_id/page/1" "$page_file")"
  assert_code "$page_code" "200" "preview.page1 fallback" "$page_file"
  echo "OK  preview page 1 (fallback legacy path)"
else
  assert_code "$page_code" "200" "preview.page1" "$page_file"
fi

text_file="$TMP_DIR/text.json"
text_code="$(http_raw GET "$API_BASE/v1/preview/$job_id/text?page=1" "$text_file")"
assert_code "$text_code" "200" "preview.text" "$text_file"
page_text="$(json_get "$text_file" "text")"
if [[ -z "$page_text" ]]; then
  echo "FAIL [preview.text] empty text response" >&2
  cat "$text_file" >&2
  exit 1
fi
echo "OK  preview text"

analyse_payload="$TMP_DIR/analyse.json"
cat >"$analyse_payload" <<JSON
{
  "file_id": "$job_id",
  "text": "proces verbal comite signature"
}
JSON

analyse_file="$TMP_DIR/analyse_response.json"
analyse_code="$(http_json POST "$API_BASE/v1/analyse" "$analyse_payload" "$analyse_file")"
assert_code "$analyse_code" "200" "analyse" "$analyse_file"
analysis_confidence="$(json_get "$analyse_file" "confidence")"
analysis_type="$(json_get "$analyse_file" "type_doc")"
echo "OK  analyse (type=$analysis_type confidence=$analysis_confidence)"

route_file="$TMP_DIR/route.json"
route_code="$(http_raw POST "$API_BASE/v1/route/$job_id" "$route_file")"
if [[ "$job_status" == "needs_review" && "$route_code" == "409" ]]; then
  echo "OK  route blocked before review (expected 409)"

  review_payload="$TMP_DIR/review.json"
  cat >"$review_payload" <<JSON
{
  "corrected_fields": {"numero": "SMOKE-001"},
  "corrected_class_code": "$REVIEW_CLASS_CODE",
  "corrected_preset": "preset_pv",
  "comment": "automated smoke review"
}
JSON
  review_file="$TMP_DIR/review_response.json"
  review_code="$(http_json POST "$API_BASE/v1/jobs/$job_id/review" "$review_payload" "$review_file")"
  assert_code "$review_code" "200" "jobs.review" "$review_file"
  echo "OK  review applied"

  route_code="$(http_raw POST "$API_BASE/v1/route/$job_id" "$route_file")"
fi

assert_code "$route_code" "200" "route" "$route_file"
resolved_folder="$(json_get "$route_file" "resolved_folder")"
echo "OK  route (folder=$resolved_folder)"

events_file="$TMP_DIR/events.json"
events_code="$(http_raw GET "$API_BASE/v1/events?cursor=0" "$events_file")"
assert_code "$events_code" "200" "events" "$events_file"
events_count="$(json_len "$events_file" "events")"
echo "OK  events (count=$events_count)"

echo
echo "Smoke test passed."
echo "job_id=$job_id"
