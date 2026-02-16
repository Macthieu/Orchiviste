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
    echo "Commande requise manquante : $cmd" >&2
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

json_all_event_ids_gt() {
  local file="$1"
  local threshold="$2"
  python3 - "$file" "$threshold" <<'PY'
import json
import sys

file_path = sys.argv[1]
threshold = int(sys.argv[2])
with open(file_path, "r", encoding="utf-8") as f:
    payload = json.load(f)
events = payload.get("events", [])
ok = all(isinstance(item.get("id"), int) and item["id"] > threshold for item in events)
print("yes" if ok else "no")
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
    echo "ECHEC [$label] HTTP attendu $expected, reçu $actual" >&2
    if [[ -f "$body_file" ]]; then
      cat "$body_file" >&2
    fi
    exit 1
  fi
}

header_get() {
  local file="$1"
  local header_name="$2"
  python3 - "$file" "$header_name" <<'PY'
import sys

file_path = sys.argv[1]
header_name = sys.argv[2].strip().lower()

with open(file_path, "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        if key.strip().lower() == header_name:
            print(value.strip())
            break
PY
}

need_cmd curl
need_cmd python3

echo "== Test fumée MVP Orchiviste =="
echo "API : $API_BASE"

health_file="$TMP_DIR/health.json"
health_code="$(http_raw GET "$API_BASE/v1/health" "$health_file")"
assert_code "$health_code" "200" "health" "$health_file"
echo "OK  santé"

forced_correlation_id="smoke-corr-$(date +%s)"
correlation_headers="$TMP_DIR/correlation_headers.txt"
correlation_body="$TMP_DIR/correlation_body.json"
correlation_code="$(curl -sS -D "$correlation_headers" -o "$correlation_body" -w "%{http_code}" \
  -H "x-correlation-id: $forced_correlation_id" \
  "$API_BASE/v1/health")"
assert_code "$correlation_code" "200" "health.correlation.propagation" "$correlation_body"
returned_correlation_id="$(header_get "$correlation_headers" "x-correlation-id")"
if [[ "$returned_correlation_id" != "$forced_correlation_id" ]]; then
  echo "ECHEC [health.correlation.propagation] x-correlation-id attendu=$forced_correlation_id reçu=$returned_correlation_id" >&2
  cat "$correlation_headers" >&2
  exit 1
fi

generated_headers="$TMP_DIR/generated_headers.txt"
generated_body="$TMP_DIR/generated_body.json"
generated_code="$(curl -sS -D "$generated_headers" -o "$generated_body" -w "%{http_code}" "$API_BASE/v1/health")"
assert_code "$generated_code" "200" "health.correlation.generation" "$generated_body"
generated_correlation_id="$(header_get "$generated_headers" "x-correlation-id")"
if [[ -z "$generated_correlation_id" ]]; then
  echo "ECHEC [health.correlation.generation] x-correlation-id absent" >&2
  cat "$generated_headers" >&2
  exit 1
fi
echo "OK  propagation et génération correlation-id"

ui_redirect_headers="$TMP_DIR/ui_redirect_headers.txt"
ui_redirect_code="$(curl -sS -D "$ui_redirect_headers" -o /dev/null -w "%{http_code}" "$API_BASE/u")"
assert_code "$ui_redirect_code" "303" "ui.alias.redirect" "$ui_redirect_headers"
if ! tr -d '\r' < "$ui_redirect_headers" | grep -qi '^location: /ui$'; then
  echo "ECHEC [ui.alias.redirect] Location attendue : /ui" >&2
  cat "$ui_redirect_headers" >&2
  exit 1
fi
echo "OK  redirection alias UI (/u -> /ui)"

jobs_bad_request_file="$TMP_DIR/jobs_bad_request.json"
jobs_bad_request_code="$(http_raw GET "$API_BASE/v1/jobs/not-a-uuid" "$jobs_bad_request_file")"
assert_code "$jobs_bad_request_code" "400" "jobs.bad_request" "$jobs_bad_request_file"

jobs_not_found_file="$TMP_DIR/jobs_not_found.json"
jobs_not_found_code="$(http_raw GET "$API_BASE/v1/jobs/00000000-0000-0000-0000-000000000000" "$jobs_not_found_file")"
assert_code "$jobs_not_found_code" "404" "jobs.not_found" "$jobs_not_found_file"

preview_bad_request_file="$TMP_DIR/preview_bad_request.json"
preview_bad_request_code="$(http_raw GET "$API_BASE/v1/preview/not-a-uuid/thumbnail" "$preview_bad_request_file")"
assert_code "$preview_bad_request_code" "400" "preview.bad_request" "$preview_bad_request_file"

preview_not_found_file="$TMP_DIR/preview_not_found.json"
preview_not_found_code="$(http_raw GET "$API_BASE/v1/preview/00000000-0000-0000-0000-000000000000/thumbnail" "$preview_not_found_file")"
assert_code "$preview_not_found_code" "404" "preview.not_found" "$preview_not_found_file"
echo "OK  erreurs HTTP 400/404 sur jobs et preview"

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
  echo "ECHEC [ingest] taskId manquant dans la réponse" >&2
  cat "$ingest_file" >&2
  exit 1
fi
echo "OK  ingestion (job_id=$job_id)"

ingest_repeat_file="$TMP_DIR/ingest_repeat.json"
ingest_repeat_code="$(http_json POST "$API_BASE/v1/ingest" "$ingest_payload" "$ingest_repeat_file" -H "Idempotency-Key: $idem_key")"
assert_code "$ingest_repeat_code" "202" "ingest.idempotent_repeat" "$ingest_repeat_file"
repeat_job_id="$(json_get "$ingest_repeat_file" "taskId")"
if [[ "$repeat_job_id" != "$job_id" ]]; then
  echo "ECHEC [ingest.idempotent_repeat] taskId identique attendu, reçu $repeat_job_id vs $job_id" >&2
  cat "$ingest_repeat_file" >&2
  exit 1
fi
echo "OK  rejeu idempotent d'ingestion"

ingest_conflict_payload="$TMP_DIR/ingest_conflict.json"
cat >"$ingest_conflict_payload" <<JSON
{
  "fileURL": "smoke-proces-verbal-different.pdf",
  "source": { "kind": "local" },
  "tags": ["smoke", "mvp"]
}
JSON
ingest_conflict_file="$TMP_DIR/ingest_conflict_response.json"
ingest_conflict_code="$(http_json POST "$API_BASE/v1/ingest" "$ingest_conflict_payload" "$ingest_conflict_file" -H "Idempotency-Key: $idem_key")"
assert_code "$ingest_conflict_code" "409" "ingest.idempotent_conflict" "$ingest_conflict_file"
echo "OK  conflit idempotent d'ingestion"

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
  echo "ECHEC [jobs] statut de tâche introuvable avant expiration" >&2
  cat "$job_file" >&2
  exit 1
fi
echo "OK  statut de tâche atteint : $job_status"

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
echo "OK  vignette d'aperçu"

page_file="$TMP_DIR/page1.jpg"
page_code="$(http_raw GET "$API_BASE/v1/preview/$job_id/page/1.jpg" "$page_file")"
assert_code "$page_code" "200" "preview.page1" "$page_file"
echo "OK  page d'aperçu 1 (.jpg)"

text_file="$TMP_DIR/text.json"
text_code="$(http_raw GET "$API_BASE/v1/preview/$job_id/text?page=1" "$text_file")"
assert_code "$text_code" "200" "preview.text" "$text_file"
page_text="$(json_get "$text_file" "text")"
if [[ -z "$page_text" ]]; then
  echo "ECHEC [preview.text] réponse texte vide" >&2
  cat "$text_file" >&2
  exit 1
fi
echo "OK  texte d'aperçu"

text_page_invalid_file="$TMP_DIR/text_page_invalid.json"
text_page_invalid_code="$(http_raw GET "$API_BASE/v1/preview/$job_id/text?page=0" "$text_page_invalid_file")"
assert_code "$text_page_invalid_code" "400" "preview.text.bad_page" "$text_page_invalid_file"
echo "OK  validation page texte (400)"

ui_job_file="$TMP_DIR/ui_job.html"
ui_job_code="$(http_raw GET "$API_BASE/ui/jobs/$job_id" "$ui_job_file")"
assert_code "$ui_job_code" "200" "ui.job.viewer" "$ui_job_file"
python3 - "$ui_job_file" "$job_id" <<'PY'
import sys

file_path = sys.argv[1]
job_id = sys.argv[2]
download_path = f"/v1/jobs/{job_id}/download"

with open(file_path, "r", encoding="utf-8", errors="replace") as f:
    html = f.read()

if "Télécharger (action explicite)" not in html:
    print("ECHEC [ui.job.viewer] libellé de téléchargement explicite absent", file=sys.stderr)
    sys.exit(1)
if f'href="{download_path}"' not in html:
    print("ECHEC [ui.job.viewer] lien explicite de téléchargement absent", file=sys.stderr)
    sys.exit(1)
if html.count(download_path) != 1:
    print("ECHEC [ui.job.viewer] le chemin de téléchargement doit apparaître une seule fois (pas d'auto-download)", file=sys.stderr)
    sys.exit(1)
if "fetch(`/v1/jobs/${jobId}/download`" in html:
    print("ECHEC [ui.job.viewer] téléchargement automatique détecté", file=sys.stderr)
    sys.exit(1)
PY
echo "OK  UI preview sans téléchargement automatique"

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
echo "OK  analyse (type=$analysis_type confiance=$analysis_confidence)"

route_file="$TMP_DIR/route.json"
route_code="$(http_raw POST "$API_BASE/v1/route/$job_id" "$route_file")"
if [[ "$job_status" == "needs_review" && "$route_code" == "409" ]]; then
  echo "OK  routage bloqué avant revue (409 attendu)"

  review_payload="$TMP_DIR/review.json"
  cat >"$review_payload" <<JSON
{
  "corrected_fields": {"numero": "SMOKE-001"},
  "corrected_class_code": "$REVIEW_CLASS_CODE",
  "corrected_preset": "preset_pv",
  "comment": "revue automatique test fumée"
}
JSON
  review_file="$TMP_DIR/review_response.json"
  review_code="$(http_json POST "$API_BASE/v1/jobs/$job_id/review" "$review_payload" "$review_file")"
  assert_code "$review_code" "200" "jobs.review" "$review_file"
  echo "OK  revue appliquée"

  route_code="$(http_raw POST "$API_BASE/v1/route/$job_id" "$route_file")"
fi

assert_code "$route_code" "200" "route" "$route_file"
resolved_folder="$(json_get "$route_file" "resolved_folder")"
echo "OK  routage (dossier=$resolved_folder)"

events_file="$TMP_DIR/events.json"
events_code="$(http_raw GET "$API_BASE/v1/events?cursor=0" "$events_file")"
assert_code "$events_code" "200" "events" "$events_file"
events_count="$(json_len "$events_file" "events")"
events_cursor="$(json_get "$events_file" "cursor")"
echo "OK  événements (nombre=$events_count curseur=$events_cursor)"

events_delta_file="$TMP_DIR/events_delta.json"
events_delta_code="$(http_raw GET "$API_BASE/v1/events?cursor=$events_cursor" "$events_delta_file")"
assert_code "$events_delta_code" "200" "events.cursor" "$events_delta_file"
ids_check="$(json_all_event_ids_gt "$events_delta_file" "$events_cursor")"
if [[ "$ids_check" != "yes" ]]; then
  echo "ECHEC [events.cursor] tous les ids d'événement doivent être > curseur=$events_cursor" >&2
  cat "$events_delta_file" >&2
  exit 1
fi
echo "OK  filtrage des événements par curseur"

echo
echo "Test fumée réussi."
echo "job_id=$job_id"
