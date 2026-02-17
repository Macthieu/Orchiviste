#!/usr/bin/env bash
set -euo pipefail

API_BASE="${ORCHIVISTE_API_BASE:-http://127.0.0.1:28780}"
REVIEW_CLASS_CODE="${ORCHIVISTE_REVIEW_CLASS_CODE:-ADM-PV}"
TIMEOUT_SECONDS="${ORCHIVISTE_RENAME_TIMEOUT:-120}"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /chemin/vers/fichier.pdf" >&2
  exit 1
fi

SOURCE_FILE="$1"
if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "ERREUR: fichier introuvable: $SOURCE_FILE" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERREUR: docker n'est pas installe ou non accessible." >&2
  exit 1
fi

if ! docker compose ps api >/dev/null 2>&1; then
  echo "ERREUR: lance ce script depuis la racine du repo (docker-compose.yml requis)." >&2
  exit 1
fi

if ! docker compose ps --status running api | grep -q "orchiviste-api"; then
  echo "ERREUR: le service api n'est pas demarre. Lance: docker compose up -d" >&2
  exit 1
fi

json_get() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import json
import sys

file_path = sys.argv[1]
query = sys.argv[2]

with open(file_path, "r", encoding="utf-8", errors="replace") as f:
    data = json.load(f)

value = data
for part in query.split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if value is None:
    print("")
elif isinstance(value, (dict, list)):
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
  curl -sS -o "$output_file" -w "%{http_code}" \
    -X "$method" \
    -H "Content-Type: application/json" \
    --data @"$payload_file" \
    "$url"
}

http_raw() {
  local method="$1"
  local url="$2"
  local output_file="$3"
  curl -sS -o "$output_file" -w "%{http_code}" -X "$method" "$url"
}

echo "Preparation du fichier local dans le conteneur API..."
docker compose exec -T api sh -lc "mkdir -p /data/inbox"
timestamp="$(date +%Y%m%d-%H%M%S)"
container_file="/data/inbox/${timestamp}-$(basename "$SOURCE_FILE")"
docker cp "$SOURCE_FILE" "orchiviste-api:$container_file"
echo "OK  fichier copie vers $container_file"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

ingest_payload="$tmp_dir/ingest.json"
cat >"$ingest_payload" <<JSON
{
  "fileURL": "$container_file",
  "source": {"kind": "local"},
  "tags": ["manuel", "pdf", "renommage"]
}
JSON

ingest_file="$tmp_dir/ingest_response.json"
ingest_code="$(http_json POST "$API_BASE/v1/ingest" "$ingest_payload" "$ingest_file")"
if [[ "$ingest_code" != "202" ]]; then
  echo "ERREUR: ingest en echec (HTTP $ingest_code)" >&2
  cat "$ingest_file" >&2
  exit 1
fi

job_id="$(json_get "$ingest_file" "taskId")"
if [[ -z "$job_id" ]]; then
  echo "ERREUR: taskId absent de la reponse d'ingestion." >&2
  cat "$ingest_file" >&2
  exit 1
fi
echo "OK  ingestion creee (job_id=$job_id)"

echo "Attente de la fin d'analyse..."
job_file="$tmp_dir/job.json"
deadline=$((SECONDS + TIMEOUT_SECONDS))
job_status=""
while (( SECONDS < deadline )); do
  code="$(http_raw GET "$API_BASE/v1/jobs/$job_id" "$job_file")"
  if [[ "$code" != "200" ]]; then
    echo "ERREUR: impossible de lire la tache (HTTP $code)." >&2
    cat "$job_file" >&2
    exit 1
  fi
  job_status="$(json_get "$job_file" "status")"
  if [[ "$job_status" == "completed" || "$job_status" == "needs_review" || "$job_status" == "failed" || "$job_status" == "cancelled" ]]; then
    break
  fi
  sleep 1
done

if [[ "$job_status" != "completed" && "$job_status" != "needs_review" ]]; then
  echo "ERREUR: statut final inattendu: $job_status" >&2
  cat "$job_file" >&2
  exit 1
fi
echo "OK  statut analyse: $job_status"

if [[ "$job_status" == "needs_review" ]]; then
  review_payload="$tmp_dir/review.json"
  cat >"$review_payload" <<JSON
{
  "corrected_class_code": "$REVIEW_CLASS_CODE",
  "corrected_preset": "preset_default",
  "comment": "validation manuelle pour test renommage local"
}
JSON
  review_file="$tmp_dir/review_response.json"
  review_code="$(http_json POST "$API_BASE/v1/jobs/$job_id/review" "$review_payload" "$review_file")"
  if [[ "$review_code" != "200" ]]; then
    echo "ERREUR: revue en echec (HTTP $review_code)." >&2
    cat "$review_file" >&2
    exit 1
  fi
  echo "OK  revue appliquee"
fi

route_file="$tmp_dir/route_response.json"
route_code="$(http_raw POST "$API_BASE/v1/route/$job_id" "$route_file")"
if [[ "$route_code" != "200" ]]; then
  echo "ERREUR: routage en echec (HTTP $route_code)." >&2
  cat "$route_file" >&2
  exit 1
fi

mode="$(json_get "$route_file" "mode")"
class_code="$(json_get "$route_file" "class_code")"
destination_local_path="$(json_get "$route_file" "destination_local_path")"

echo "OK  routage termine (mode=$mode, class_code=$class_code)"
if [[ -n "$destination_local_path" ]]; then
  echo "Destination locale: $destination_local_path"
  escaped_dest="${destination_local_path//\"/\\\"}"
  if docker compose exec -T api sh -lc "test -f \"$escaped_dest\""; then
    echo "OK  fichier present a la destination."
  else
    echo "ERREUR: fichier absent a la destination." >&2
    exit 1
  fi
else
  echo "ATTENTION: destination_local_path vide (mode=$mode)." >&2
fi

escaped_source="${container_file//\"/\\\"}"
if docker compose exec -T api sh -lc "test ! -f \"$escaped_source\""; then
  echo "OK  fichier source deplace (plus present dans inbox)."
else
  echo "ATTENTION: fichier source encore present dans inbox." >&2
fi

echo
echo "Test termine."
echo "job_id=$job_id"
