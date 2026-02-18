#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE="${ORCHIVISTE_API_BASE:-http://127.0.0.1:28780}"
WORKER_IMAGE="${ORCHIVISTE_WORKER_IMAGE:-orchiviste-worker:latest}"
TIMEOUT_SECONDS="${ORCHIVISTE_WORKER_SMOKE_TIMEOUT:-60}"

timestamp="$(date +%s)"
WORKER_NAME="${ORCHIVISTE_WORKER_SMOKE_NAME:-worker-smoke-${timestamp}}"
WORKER_CONTAINER="${ORCHIVISTE_WORKER_SMOKE_CONTAINER:-orchiviste-worker-smoke-${timestamp}}"
TMP_DIR="$(mktemp -d)"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Commande requise manquante : $cmd" >&2
    exit 1
  fi
}

cleanup() {
  docker rm -f "$WORKER_CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

need_cmd curl
need_cmd docker
need_cmd jq

echo "== Test fumée worker control-plane Orchiviste =="
echo "API : $API_BASE"
echo "Worker test : $WORKER_NAME"

if ! curl -sS -f "$API_BASE/v1/health" >/dev/null 2>&1; then
  echo "ÉCHEC : API non joignable sur $API_BASE/v1/health" >&2
  exit 1
fi

cd "$ROOT_DIR"

docker compose up -d api analyse redis >/dev/null

if ! docker image inspect "$WORKER_IMAGE" >/dev/null 2>&1; then
  echo "INFO: image worker absente, build en cours..."
  docker compose --profile worker build worker >/dev/null
fi

docker compose --profile worker run -d --name "$WORKER_CONTAINER" --no-deps \
  -e "ORCHIVISTE_WORKER_NAME=$WORKER_NAME" \
  -e "ORCHIVISTE_WORKER_STATE_PATH=/tmp/${WORKER_NAME}-state.json" \
  -e "ORCHIVISTE_WORKER_HEARTBEAT_SECONDS=2" \
  -e "ORCHIVISTE_WORKER_APPROVAL_POLL_SECONDS=1" \
  -e "ORCHIVISTE_WORKER_WAIT_FOR_APPROVAL=1" \
  -e "ORCHIVISTE_WORKER_AUTO_APPROVE=0" \
  -e "ORCHIVISTE_WORKER_ENABLE_QUEUE=0" \
  worker >/dev/null

deadline=$((SECONDS + TIMEOUT_SECONDS))
worker_id=""
worker_status=""
while (( SECONDS < deadline )); do
  workers_file="$TMP_DIR/workers-enroll.json"
  if curl -sS "$API_BASE/v1/workers" >"$workers_file"; then
    worker_id="$(jq -r --arg name "$WORKER_NAME" '.[] | select(.name == $name) | .id' "$workers_file" | head -n 1)"
    worker_status="$(jq -r --arg name "$WORKER_NAME" '.[] | select(.name == $name) | .status' "$workers_file" | head -n 1)"
    if [[ -n "$worker_id" && "$worker_id" != "null" ]]; then
      break
    fi
  fi
  sleep 1
done

if [[ -z "$worker_id" || "$worker_id" == "null" ]]; then
  echo "ÉCHEC : agent non enrôlé dans le délai." >&2
  docker logs "$WORKER_CONTAINER" >&2 || true
  exit 1
fi

if [[ "$worker_status" != "pending" ]]; then
  echo "ÉCHEC : statut initial inattendu (attendu=pending reçu=$worker_status)." >&2
  docker logs "$WORKER_CONTAINER" >&2 || true
  exit 1
fi
echo "OK  enrôlement pending (worker_id=$worker_id)"

approve_file="$TMP_DIR/approve.json"
approve_code="$(
  curl -sS -o "$approve_file" -w "%{http_code}" \
    -X POST "$API_BASE/v1/workers/$worker_id/approve"
)"
if [[ "$approve_code" != "200" ]]; then
  echo "ÉCHEC : approbation worker en erreur (HTTP $approve_code)." >&2
  cat "$approve_file" >&2 || true
  exit 1
fi

token="$(jq -r '.token // empty' "$approve_file")"
if [[ -z "$token" ]]; then
  echo "ÉCHEC : jeton agent absent après approbation." >&2
  cat "$approve_file" >&2 || true
  exit 1
fi
echo "OK  approbation worker + jeton"

heartbeat_ok="0"
deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  workers_file="$TMP_DIR/workers-heartbeat.json"
  if curl -sS "$API_BASE/v1/workers" >"$workers_file"; then
    status="$(jq -r --arg id "$worker_id" '.[] | select(.id == $id) | .status' "$workers_file" | head -n 1)"
    last_seen="$(jq -r --arg id "$worker_id" '.[] | select(.id == $id) | .lastSeen // empty' "$workers_file" | head -n 1)"
    if [[ "$status" == "approved" && -n "$last_seen" ]]; then
      heartbeat_ok="1"
      break
    fi
  fi
  sleep 1
done

if [[ "$heartbeat_ok" != "1" ]]; then
  echo "ÉCHEC : heartbeat non observé dans le délai." >&2
  docker logs "$WORKER_CONTAINER" >&2 || true
  exit 1
fi

echo "OK  heartbeat reçu (lastSeen renseigné)"
echo "Test fumée worker control-plane réussi."
