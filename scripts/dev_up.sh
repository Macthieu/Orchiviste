#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE="${ORCHIVISTE_API_BASE:-http://127.0.0.1:28780}"
ANALYSE_BASE="${ORCHIVISTE_ANALYSE_BASE:-http://127.0.0.1:28781}"
START_TIMEOUT="${ORCHIVISTE_DEV_START_TIMEOUT:-120}"
BUILD_ON_START="${ORCHIVISTE_DEV_BUILD_ON_START:-0}"
USE_CLASSIC_BUILDER="${ORCHIVISTE_DEV_CLASSIC_BUILDER:-0}"
FALLBACK_CLASSIC_BUILDER="${ORCHIVISTE_DEV_FALLBACK_CLASSIC_BUILDER:-1}"
ALLOW_LOCAL_PORT_CONFLICT="${ORCHIVISTE_DEV_ALLOW_LOCAL_PORT_CONFLICT:-0}"
ANON_AUTH="${ORCHIVISTE_DOCKER_ANON_AUTH:-0}"
DOCKER_CONFIG_ORIGINAL="${DOCKER_CONFIG:-}"
DOCKER_CONFIG_OVERRIDE=""
DOCKER_INFO_TIMEOUT="${ORCHIVISTE_DOCKER_INFO_TIMEOUT:-8}"

usage() {
  cat <<'EOF'
Usage: ./scripts/dev_up.sh [options]

Options:
  --build            force un build des images avant démarrage
  --no-build         n'effectue pas de build (défaut)
  --classic-builder  utilise le builder classique (BuildKit désactivé)
  --anon-auth        contourne docker-credential-desktop (auth registre anonyme)
  --help             affiche cette aide

Variables d'environnement:
  ORCHIVISTE_DEV_BUILD_ON_START=1
  ORCHIVISTE_DEV_CLASSIC_BUILDER=1
  ORCHIVISTE_DEV_FALLBACK_CLASSIC_BUILDER=0|1
  ORCHIVISTE_DEV_ALLOW_LOCAL_PORT_CONFLICT=0|1
  ORCHIVISTE_DEV_START_TIMEOUT=120
  ORCHIVISTE_DOCKER_INFO_TIMEOUT=8
  ORCHIVISTE_DOCKER_ANON_AUTH=1
EOF
}

while (($# > 0)); do
  case "$1" in
    --build)
      BUILD_ON_START="1"
      ;;
    --no-build)
      BUILD_ON_START="0"
      ;;
    --classic-builder)
      USE_CLASSIC_BUILDER="1"
      ;;
    --anon-auth)
      ANON_AUTH="1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Option inconnue : $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Commande requise manquante : $cmd" >&2
    exit 1
  fi
}

port_from_url() {
  local url="$1"
  local without_scheme="${url#*://}"
  local host_port="${without_scheme%%/*}"
  if [[ "$host_port" == *:* ]]; then
    printf '%s\n' "${host_port##*:}"
  else
    printf '%s\n' ""
  fi
}

check_local_listener_conflicts() {
  if [[ "$ALLOW_LOCAL_PORT_CONFLICT" == "1" ]]; then
    return 0
  fi
  if ! command -v lsof >/dev/null 2>&1; then
    return 0
  fi

  local api_port analyse_port
  api_port="$(port_from_url "$API_BASE")"
  analyse_port="$(port_from_url "$ANALYSE_BASE")"

  for port in "$api_port" "$analyse_port"; do
    [[ -n "$port" ]] || continue
    local lines
    lines="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 && index($1, "com.docke") != 1 {print $1" "$2" "$9}')"
    if [[ -n "$lines" ]]; then
      echo "ÉCHEC : conflit de port local détecté sur $port." >&2
      echo "Processus non-Docker en écoute :" >&2
      echo "$lines" >&2
      echo "Arrête ce processus local (ou exporte ORCHIVISTE_DEV_ALLOW_LOCAL_PORT_CONFLICT=1 si c'est volontaire)." >&2
      exit 1
    fi
  done
}

docker_info_ok() {
  local timeout_seconds="${1:-8}"
  python3 - "$timeout_seconds" <<'PY'
import subprocess
import sys

timeout = max(1, int(sys.argv[1]))
try:
    subprocess.run(
        ["docker", "info"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
        check=True,
    )
except Exception:
    sys.exit(1)
sys.exit(0)
PY
}

wait_for_docker_daemon() {
  local deadline=$((SECONDS + START_TIMEOUT))

  if docker_info_ok "$DOCKER_INFO_TIMEOUT"; then
    return 0
  fi

  if [[ "${OSTYPE:-}" == darwin* ]] && command -v open >/dev/null 2>&1; then
    echo "Docker daemon indisponible. Tentative de démarrage Docker Desktop..."
    open -a Docker >/dev/null 2>&1 || true
  fi

  while (( SECONDS < deadline )); do
    if docker_info_ok "$DOCKER_INFO_TIMEOUT"; then
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

compose_cmd() {
  if [[ "$USE_CLASSIC_BUILDER" == "1" ]]; then
    DOCKER_BUILDKIT=0 COMPOSE_DOCKER_CLI_BUILD=0 docker compose "$@"
  else
    docker compose "$@"
  fi
}

setup_auth_mode() {
  if [[ "$ANON_AUTH" != "1" ]]; then
    return
  fi

  DOCKER_CONFIG_OVERRIDE="$(mktemp -d)"
  cat >"$DOCKER_CONFIG_OVERRIDE/config.json" <<'EOF'
{"auths":{"https://index.docker.io/v1/":{}}}
EOF

  if [[ -d "$HOME/.docker/cli-plugins" ]]; then
    mkdir -p "$DOCKER_CONFIG_OVERRIDE/cli-plugins"
    for plugin in "$HOME/.docker/cli-plugins/"*; do
      [[ -e "$plugin" ]] || continue
      ln -s "$plugin" "$DOCKER_CONFIG_OVERRIDE/cli-plugins/$(basename "$plugin")"
    done
  fi

  export DOCKER_CONFIG="$DOCKER_CONFIG_OVERRIDE"
  echo "Mode auth registre anonyme activé (contournement docker-credential-desktop)."
}

cleanup_auth_mode() {
  if [[ "$ANON_AUTH" != "1" ]]; then
    return
  fi

  if [[ -n "$DOCKER_CONFIG_ORIGINAL" ]]; then
    export DOCKER_CONFIG="$DOCKER_CONFIG_ORIGINAL"
  else
    unset DOCKER_CONFIG
  fi

  if [[ -n "$DOCKER_CONFIG_OVERRIDE" && -d "$DOCKER_CONFIG_OVERRIDE" ]]; then
    rm -rf "$DOCKER_CONFIG_OVERRIDE"
  fi
}

compose_up_with_optional_build() {
  local with_build="$1"
  if [[ "$with_build" == "1" ]]; then
    compose_cmd up --build -d
  else
    compose_cmd up -d
  fi
}

start_stack() {
  if compose_up_with_optional_build "$BUILD_ON_START"; then
    return 0
  fi

  if [[ "$BUILD_ON_START" == "0" ]]; then
    echo "Échec du démarrage sans build, nouvelle tentative avec build..."
    BUILD_ON_START="1"
    if compose_up_with_optional_build "1"; then
      return 0
    fi
  fi

  if [[ "$USE_CLASSIC_BUILDER" == "0" && "$FALLBACK_CLASSIC_BUILDER" == "1" ]]; then
    echo "Échec avec BuildKit, nouvelle tentative en builder classique..."
    USE_CLASSIC_BUILDER="1"
    compose_up_with_optional_build "1"
    return 0
  fi

  echo "ÉCHEC : impossible de démarrer la stack Orchiviste." >&2
  exit 1
}

need_cmd docker
need_cmd curl

setup_auth_mode
trap cleanup_auth_mode EXIT

echo "== Orchiviste démarrage local =="
wait_for_docker_daemon

cd "$ROOT_DIR"
check_local_listener_conflicts
start_stack

wait_http_ok "$API_BASE/v1/health" "API"
wait_http_ok "$ANALYSE_BASE/v1/health" "Analyse"

echo
echo "Services démarrés :"
echo "- UI: ${API_BASE}/u"
echo "- API health: ${API_BASE}/v1/health"
echo "- Analyse health: ${ANALYSE_BASE}/v1/health"
echo
echo "État compose :"
compose_cmd ps
