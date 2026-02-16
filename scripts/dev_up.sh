#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE="${ORCHIVISTE_API_BASE:-http://127.0.0.1:28780}"
ANALYSE_BASE="${ORCHIVISTE_ANALYSE_BASE:-http://127.0.0.1:28781}"
START_TIMEOUT="${ORCHIVISTE_DEV_START_TIMEOUT:-120}"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Commande requise manquante : $cmd" >&2
    exit 1
  fi
}

wait_for_docker_daemon() {
  local deadline=$((SECONDS + START_TIMEOUT))

  if docker info >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${OSTYPE:-}" == darwin* ]] && command -v open >/dev/null 2>&1; then
    echo "Docker daemon indisponible. Tentative de démarrage Docker Desktop..."
    open -a Docker >/dev/null 2>&1 || true
  fi

  while (( SECONDS < deadline )); do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "ÉCHEC : impossible de joindre le daemon Docker après ${START_TIMEOUT}s." >&2
  echo "Vérifie que Docker Desktop est lancé puis relance ./scripts/dev_up.sh." >&2
  exit 1
}

wait_http_ok() {
  local url="$1"
  local label="$2"
  local deadline=$((SECONDS + START_TIMEOUT))

  while (( SECONDS < deadline )); do
    if curl -sS -f "$url" >/dev/null 2>&1; then
      echo "OK  $label prêt ($url)"
      return 0
    fi
    sleep 1
  done

  echo "ÉCHEC : $label non prêt après ${START_TIMEOUT}s ($url)." >&2
  exit 1
}

need_cmd docker
need_cmd curl

echo "== Orchiviste démarrage local =="
wait_for_docker_daemon

cd "$ROOT_DIR"
docker compose up --build -d

wait_http_ok "$API_BASE/v1/health" "API"
wait_http_ok "$ANALYSE_BASE/v1/health" "Analyse"

echo
echo "Services démarrés :"
echo "- UI: ${API_BASE}/u"
echo "- API health: ${API_BASE}/v1/health"
echo "- Analyse health: ${ANALYSE_BASE}/v1/health"
echo
echo "État compose :"
docker compose ps
