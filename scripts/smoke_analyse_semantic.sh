#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

ANALYSE_PORT="${ORCHIVISTE_ANALYSE_TEST_PORT:-}"
ANALYSE_LOG="$TMP_DIR/analyse.log"

cleanup() {
  if [[ -n "${ANALYSE_PID:-}" ]]; then
    kill "$ANALYSE_PID" >/dev/null 2>&1 || true
    wait "$ANALYSE_PID" >/dev/null 2>&1 || true
  fi
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

need_cmd curl
need_cmd python3

if [[ -z "$ANALYSE_PORT" ]]; then
  ANALYSE_PORT="$(pick_port)"
fi

echo "== Test fumee capture intelligente OrchivisteAnalyse =="
echo "Port Analyse : $ANALYSE_PORT"

(
  cd "$ROOT_DIR/OrchivisteAnalyse"
  ORCHIVISTE_ANALYSE_HOST=127.0.0.1 \
  ORCHIVISTE_ANALYSE_PORT="$ANALYSE_PORT" \
  ./.build/debug/OrchivisteAnalyse >"$ANALYSE_LOG" 2>&1
) &
ANALYSE_PID=$!

for _ in $(seq 1 60); do
  if ! kill -0 "$ANALYSE_PID" >/dev/null 2>&1; then
    echo "ECHEC : OrchivisteAnalyse s'est arrêté pendant le smoke sémantique." >&2
    tail -n 120 "$ANALYSE_LOG" >&2 || true
    exit 1
  fi
  if curl -sS "http://127.0.0.1:$ANALYSE_PORT/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

multi_payload="$TMP_DIR/multi.json"
cat >"$multi_payload" <<'JSON'
{
  "file_id": "resolution-lot.pdf",
  "lang": "fr",
  "text": "EXTRAIT DU PROCES-VERBAL\nRESOLUTION 2024-001\n2024-03-14\nATTENDU QUE le conseil souhaite autoriser la depense.\nIL EST RESOLU d'autoriser le contrat.\n\nRESOLUTION 2024-002\n2024-03-14\nATTENDU QUE le conseil souhaite autoriser la depense.\nIL EST RESOLU d'autoriser l'avenant."
}
JSON

multi_response="$TMP_DIR/multi-response.json"
multi_code="$(curl -sS -o "$multi_response" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -X POST "http://127.0.0.1:$ANALYSE_PORT/v1/analyse" \
  --data-binary "@$multi_payload")"
if [[ "$multi_code" != "200" ]]; then
  echo "ECHEC : analyse multi-unites HTTP $multi_code" >&2
  cat "$multi_response" >&2 || true
  exit 1
fi

python3 - "$multi_response" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    payload = json.load(f)

review = payload.get("review") or {}
capture = payload.get("capture") or {}

if review.get("needs_review") is not True:
    print("ECHEC : review.needs_review doit etre true")
    sys.exit(1)
if "multi_document_units" not in (review.get("reasons") or []):
    print("ECHEC : raison multi_document_units absente")
    sys.exit(1)
if int(capture.get("unit_count") or 0) < 2:
    print("ECHEC : capture.unit_count attendu >= 2")
    sys.exit(1)
print("OK  multi-unites -> needs_review + segmentation")
PY

single_payload="$TMP_DIR/single.json"
cat >"$single_payload" <<'JSON'
{
  "file_id": "resolution-2024-015.pdf",
  "lang": "fr",
  "policy": { "min_confidence": 0.60 },
  "text": "MUNICIPALITE DE TEST\nRESOLUTION 2024-015\n14 avril 2024\nOBJET: Acquisition d'equipement informatique\nATTENDU QUE des achats sont requis.\nIL EST RESOLU d'autoriser l'acquisition."
}
JSON

single_response="$TMP_DIR/single-response.json"
single_code="$(curl -sS -o "$single_response" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -X POST "http://127.0.0.1:$ANALYSE_PORT/v1/analyse" \
  --data-binary "@$single_payload")"
if [[ "$single_code" != "200" ]]; then
  echo "ECHEC : analyse unitaire HTTP $single_code" >&2
  cat "$single_response" >&2 || true
  exit 1
fi

python3 - "$single_response" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    payload = json.load(f)

capture = payload.get("capture") or {}
field_sources = capture.get("field_sources") or {}
review = payload.get("review") or {}

if payload.get("type_doc") != "Resolution":
    print("ECHEC : type_doc attendu Resolution")
    sys.exit(1)
if not capture.get("strategy"):
    print("ECHEC : capture.strategy absent")
    sys.exit(1)
if "resolution_numero" not in field_sources:
    print("ECHEC : field_sources resolution_numero absent")
    sys.exit(1)
if review.get("needs_review") not in (False, None):
    print("ECHEC : single resolution ne doit pas forcer la revue")
    sys.exit(1)
print("OK  resolution simple -> capture renseignee sans revue")
PY

echo "Test fumee capture intelligente reussi."
