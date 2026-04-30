#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

API_BASE="${ORCHIVISTE_API_BASE:-http://127.0.0.1:28780}"
ANALYSE_BASE="${ORCHIVISTE_ANALYSE_BASE:-http://127.0.0.1:28781}"
REDIS_URL="${ORCHIVISTE_REDIS_URL:-redis://127.0.0.1:6379}"
START_TIMEOUT="${ORCHIVISTE_PREFLIGHT_START_TIMEOUT:-60}"
ALLOW_DOCKER="${ORCHIVISTE_PREFLIGHT_ALLOW_DOCKER:-0}"
BUILD_NATIVE="${ORCHIVISTE_PREFLIGHT_BUILD_ON_START:-0}"
KEEP_RUNTIME="${ORCHIVISTE_PREFLIGHT_KEEP_RUNTIME:-0}"
REDIS_INGEST_KEY="${ORCHIVISTE_REDIS_INGEST_KEY:-orchiviste:preflight:$$:ingest}"
REDIS_DEADLETTER_KEY="${ORCHIVISTE_REDIS_DEADLETTER_KEY:-orchiviste:preflight:$$:dead-letter}"

RUN_WEBHOOK="1"
RUN_WORKER="1"
RUN_GRAPH="1"
RUN_MUNICONV_RESUME="1"
SKIP_UP="0"
run_pdf_batch="0"
start_epoch="$(date +%s)"

ignored_docker_args=()
pdf_inputs=()
API_PID=""
ANALYSE_PID=""
REDIS_PID=""
NATIVE_RUNTIME_DIR=""

usage() {
  cat <<'EOF'
Usage: ./scripts/preflight_local.sh [options]

Modes:
  --full            validation complète (défaut) : smoke + openapi + webhook + graph + reprise MuniConversion
  --quick           validation rapide : smoke + openapi (sans webhook, sans worker, sans graph, sans reprise MuniConversion)

Options:
  --skip-up         ne démarre pas la stack native (services déjà démarrés)
  --with-worker     force l'exécution du test worker (même en mode --quick)
  --no-worker       ignore le test worker (même en mode --full)
  --pdf <path>      lance aussi le test batch de renommage sur fichier/dossier PDF
                    option répétable, ex: --pdf ~/Documents --pdf ~/a.pdf
  --build           force le build natif API + Analyse avant démarrage
  --no-build        ne rebuild pas si les binaires natifs existent (défaut)
  --classic-builder accepté par compatibilité, ignoré en mode natif
  --anon-auth       accepté par compatibilité, ignoré en mode natif
  --help            affiche cette aide

Variables:
  ORCHIVISTE_PREFLIGHT_ALLOW_DOCKER=1 autorise les smokes hérités qui dépendent encore de Docker
EOF
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Commande requise manquante : $cmd" >&2
    exit 1
  fi
}

docker_available() {
  command -v docker >/dev/null 2>&1
}

http_ok() {
  local url="$1"
  curl -fsS "$url" >/dev/null 2>&1
}

url_part() {
  local url="$1"
  local part="$2"
  python3 - "$url" "$part" <<'PY'
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
part = sys.argv[2]

if part == "host":
    print(parsed.hostname or "127.0.0.1")
elif part == "port":
    if parsed.port:
        print(parsed.port)
    elif parsed.scheme == "redis":
        print(6379)
    elif parsed.scheme == "https":
        print(443)
    else:
        print(80)
PY
}

cleanup_native_stack() {
  for pid in "$API_PID" "$ANALYSE_PID" "$REDIS_PID"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done

  if [[ -n "$NATIVE_RUNTIME_DIR" && "$KEEP_RUNTIME" != "1" ]]; then
    rm -rf "$NATIVE_RUNTIME_DIR"
  elif [[ -n "$NATIVE_RUNTIME_DIR" ]]; then
    echo "INFO: runtime préflight conservé : $NATIVE_RUNTIME_DIR"
  fi
}
trap cleanup_native_stack EXIT

ensure_native_product() {
  local product="$1"
  local package_dir="$2"
  local binary="$package_dir/.build/debug/$product"

  if [[ "$BUILD_NATIVE" == "1" || ! -x "$binary" ]]; then
    need_cmd swift
    echo "== Build natif $product =="
    (cd "$package_dir" && swift build -c debug --product "$product")
  fi

  if [[ ! -x "$binary" ]]; then
    echo "ECHEC: binaire natif introuvable: $binary" >&2
    exit 1
  fi
}

wait_http_ready() {
  local url="$1"
  local label="$2"
  local pid="$3"
  local log_file="$4"
  local deadline=$((SECONDS + START_TIMEOUT))

  while (( SECONDS < deadline )); do
    if [[ -n "$pid" ]] && ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "ECHEC: $label s'est arrêté pendant le démarrage natif." >&2
      [[ -f "$log_file" ]] && tail -n 120 "$log_file" >&2 || true
      exit 1
    fi
    if http_ok "$url"; then
      echo "OK  $label prêt ($url)"
      return 0
    fi
    sleep 1
  done

  echo "ECHEC: $label non prêt après ${START_TIMEOUT}s ($url)." >&2
  [[ -f "$log_file" ]] && tail -n 120 "$log_file" >&2 || true
  exit 1
}

ensure_runtime_dir() {
  if [[ -z "$NATIVE_RUNTIME_DIR" ]]; then
    local raw_dir
    raw_dir="$(mktemp -d "${TMPDIR:-/tmp}/orchiviste-preflight-XXXXXX")"
    NATIVE_RUNTIME_DIR="$(cd "$raw_dir" && pwd -P)"
    mkdir -p "$NATIVE_RUNTIME_DIR/logs" "$NATIVE_RUNTIME_DIR/routed" "$NATIVE_RUNTIME_DIR/cockpit"
  fi
}

start_native_analyse_if_needed() {
  if http_ok "${ANALYSE_BASE%/}/v1/health"; then
    echo "OK  Analyse déjà disponible (${ANALYSE_BASE%/}/v1/health)"
    return 0
  fi

  ensure_runtime_dir
  ensure_native_product "OrchivisteAnalyse" "$ROOT_DIR/OrchivisteAnalyse"

  local analyse_host analyse_port analyse_log
  analyse_host="$(url_part "$ANALYSE_BASE" host)"
  analyse_port="$(url_part "$ANALYSE_BASE" port)"
  analyse_log="$NATIVE_RUNTIME_DIR/logs/analyse.log"

  echo "== Démarrage natif OrchivisteAnalyse =="
  (
    cd "$ROOT_DIR/OrchivisteAnalyse"
    ORCHIVISTE_ANALYSE_HOST="$analyse_host" \
    ORCHIVISTE_ANALYSE_PORT="$analyse_port" \
    ./.build/debug/OrchivisteAnalyse >"$analyse_log" 2>&1
  ) &
  ANALYSE_PID=$!

  wait_http_ready "${ANALYSE_BASE%/}/v1/health" "Analyse" "$ANALYSE_PID" "$analyse_log"
}

redis_ping() {
  command -v redis-cli >/dev/null 2>&1 && redis-cli -u "$REDIS_URL" ping >/dev/null 2>&1
}

start_native_redis_if_needed() {
  if redis_ping; then
    echo "OK  Redis déjà disponible ($REDIS_URL)"
    return 0
  fi

  if ! command -v redis-server >/dev/null 2>&1; then
    echo "ECHEC: Redis natif indisponible ($REDIS_URL)." >&2
    echo "Installe ou démarre Redis localement pour le smoke MVP, sans Docker." >&2
    exit 1
  fi

  ensure_runtime_dir

  local redis_host redis_port redis_log
  redis_host="$(url_part "$REDIS_URL" host)"
  redis_port="$(url_part "$REDIS_URL" port)"
  redis_log="$NATIVE_RUNTIME_DIR/logs/redis.log"

  echo "== Démarrage natif Redis =="
  redis-server \
    --bind "$redis_host" \
    --port "$redis_port" \
    --save "" \
    --appendonly no \
    --dir "$NATIVE_RUNTIME_DIR" \
    >"$redis_log" 2>&1 &
  REDIS_PID=$!

  local deadline=$((SECONDS + START_TIMEOUT))
  while (( SECONDS < deadline )); do
    if ! kill -0 "$REDIS_PID" >/dev/null 2>&1; then
      echo "ECHEC: Redis s'est arrêté pendant le démarrage natif." >&2
      [[ -f "$redis_log" ]] && tail -n 120 "$redis_log" >&2 || true
      exit 1
    fi
    if redis_ping; then
      echo "OK  Redis prêt ($REDIS_URL)"
      return 0
    fi
    sleep 1
  done

  echo "ECHEC: Redis non prêt après ${START_TIMEOUT}s ($REDIS_URL)." >&2
  [[ -f "$redis_log" ]] && tail -n 120 "$redis_log" >&2 || true
  exit 1
}

start_native_api_if_needed() {
  if http_ok "${API_BASE%/}/v1/health"; then
    echo "OK  API déjà disponible (${API_BASE%/}/v1/health)"
    return 0
  fi

  ensure_runtime_dir
  ensure_native_product "OrchivisteAPI" "$ROOT_DIR/OrchivisteAPI"

  local api_host api_port api_log sqlite_path
  api_host="$(url_part "$API_BASE" host)"
  api_port="$(url_part "$API_BASE" port)"
  api_log="$NATIVE_RUNTIME_DIR/logs/api.log"
  sqlite_path="$NATIVE_RUNTIME_DIR/orchiviste-preflight.sqlite"

  echo "== Démarrage natif OrchivisteAPI =="
  (
    cd "$ROOT_DIR/OrchivisteAPI"
    ORCHIVISTE_API_HOST="$api_host" \
    ORCHIVISTE_API_PORT="$api_port" \
    ORCHIVISTE_AUTO_MIGRATE=1 \
    ORCHIVISTE_SQLITE_PATH="$sqlite_path" \
    ORCHIVISTE_ANALYSE_URL="$ANALYSE_BASE" \
    ORCHIVISTE_REDIS_URL="$REDIS_URL" \
    ORCHIVISTE_REDIS_INGEST_KEY="$REDIS_INGEST_KEY" \
    ORCHIVISTE_REDIS_DEADLETTER_KEY="$REDIS_DEADLETTER_KEY" \
    ORCHIVISTE_LOCAL_ROUTE_ROOT="$NATIVE_RUNTIME_DIR/routed" \
    ORCHIVISTE_COCKPIT_RUNTIME_DIR="$NATIVE_RUNTIME_DIR/cockpit" \
    ./.build/debug/OrchivisteAPI >"$api_log" 2>&1
  ) &
  API_PID=$!

  wait_http_ready "${API_BASE%/}/v1/health" "API" "$API_PID" "$api_log"
}

start_native_stack() {
  need_cmd curl
  need_cmd python3

  if docker_available; then
    echo "INFO: préflight local en mode natif macOS; Docker ignoré."
  else
    echo "INFO: Docker non disponible; préflight local en mode natif macOS."
  fi

  if ((${#ignored_docker_args[@]} > 0)); then
    echo "INFO: option(s) Docker ignorée(s) en mode natif: ${ignored_docker_args[*]}"
  fi

  start_native_analyse_if_needed
  start_native_redis_if_needed
  start_native_api_if_needed
}

while (($# > 0)); do
  case "$1" in
    --full)
      RUN_WEBHOOK="1"
      RUN_WORKER="1"
      RUN_MUNICONV_RESUME="1"
      ;;
    --quick)
      RUN_WEBHOOK="0"
      RUN_WORKER="0"
      RUN_GRAPH="0"
      RUN_MUNICONV_RESUME="0"
      ;;
    --skip-up)
      SKIP_UP="1"
      ;;
    --with-worker)
      RUN_WORKER="1"
      ;;
    --no-worker)
      RUN_WORKER="0"
      ;;
    --with-graph)
      RUN_GRAPH="1"
      ;;
    --no-graph)
      RUN_GRAPH="0"
      ;;
    --pdf)
      shift
      if (($# == 0)); then
        echo "ERREUR: --pdf requiert un chemin." >&2
        exit 1
      fi
      pdf_inputs+=("$1")
      run_pdf_batch="1"
      ;;
    --build)
      BUILD_NATIVE="1"
      ;;
    --no-build)
      BUILD_NATIVE="0"
      ;;
    --classic-builder|--anon-auth)
      ignored_docker_args+=("$1")
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Option inconnue: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

cd "$ROOT_DIR"
echo "== Préflight local Orchiviste =="
if [[ "$RUN_WEBHOOK" == "1" ]]; then
  echo "Mode: complet"
else
  echo "Mode: rapide"
fi

if [[ "$SKIP_UP" == "1" ]]; then
  echo "INFO: démarrage stack native ignoré (--skip-up)."
else
  start_native_stack
fi

./scripts/check_openapi_mvp.sh
./scripts/smoke_analyse_semantic.sh
./scripts/smoke_mvp.sh
./scripts/smoke_metrics.sh

if [[ "$RUN_GRAPH" == "1" ]]; then
  ./scripts/smoke_graph_router.sh
else
  echo "INFO: test Graph ignoré (mode rapide ou --no-graph)."
fi

if [[ "$RUN_WEBHOOK" == "1" ]]; then
  ./scripts/smoke_webhook_hmac.sh
else
  echo "INFO: test webhook ignoré (--quick)."
fi

if [[ "$RUN_WORKER" == "1" ]]; then
  if [[ "$ALLOW_DOCKER" == "1" ]] && docker_available; then
    ./scripts/smoke_worker_controlplane.sh
  else
    echo "INFO: test worker ignoré (dépendance Docker; exporte ORCHIVISTE_PREFLIGHT_ALLOW_DOCKER=1 pour l'exécuter)."
  fi
else
  echo "INFO: test worker ignoré (mode rapide ou --no-worker)."
fi

if [[ "$RUN_MUNICONV_RESUME" == "1" ]]; then
  echo "== Smoke reprise employé MuniConversion =="
  ./scripts/smoke_muni_conversion_employee_resume.sh
else
  echo "INFO: smoke reprise employé MuniConversion ignoré (--quick)."
fi

if [[ "$run_pdf_batch" == "1" ]]; then
  if [[ "$ALLOW_DOCKER" == "1" ]] && docker_available; then
    ./scripts/test_pdf_rename_batch.sh "${pdf_inputs[@]}"
  else
    echo "INFO: test batch PDF ignoré (dépendance Docker; exporte ORCHIVISTE_PREFLIGHT_ALLOW_DOCKER=1 pour l'exécuter)."
  fi
fi

./scripts/smoke_regression_dataset.sh

elapsed=$(( $(date +%s) - start_epoch ))
echo
echo "Préflight local réussi en ${elapsed}s."
