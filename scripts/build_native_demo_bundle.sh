#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
DEFAULT_BUNDLE_DIR="$PARENT_DIR/Orchiviste-demo-macOS"
BUNDLE_DIR="${1:-$DEFAULT_BUNDLE_DIR}"

if [[ "$BUNDLE_DIR" != /* ]]; then
  BUNDLE_DIR="$ROOT_DIR/$BUNDLE_DIR"
fi

BIN_DIR="$BUNDLE_DIR/bin"
CONFIG_DIR="$BUNDLE_DIR/configs"
VIEWS_DIR="$BUNDLE_DIR/resources/Views"
MODELS_DIR="$BUNDLE_DIR/models-coreml"
MODELS_SRC_DIR="$BUNDLE_DIR/models-src"
LOG_DIR="$BUNDLE_DIR/logs"
RUN_DIR="$BUNDLE_DIR/run"
DB_DIR="$BUNDLE_DIR/state/db"
UI_STATE_DIR="$BUNDLE_DIR/state/ui"
DATA_INBOX_DIR="$BUNDLE_DIR/data/inbox"
DATA_ROUTED_DIR="$BUNDLE_DIR/data/routed"
DATA_BACKUP_DIR="$BUNDLE_DIR/data/backups"

build_product() {
  local module="$1"
  local product="$2"
  echo "==> Build release $product"
  (
    cd "$ROOT_DIR/$module"
    swift build -c release --product "$product"
  )
}

find_release_binary() {
  local module="$1"
  local product="$2"
  find "$ROOT_DIR/$module/.build" -type f -path "*/release/$product" | head -n 1
}

write_file() {
  local target="$1"
  shift
  mkdir -p "$(dirname "$target")"
  cat > "$target"
}

build_product "OrchivisteAnalyse" "OrchivisteAnalyse"
build_product "OrchivisteAPI" "OrchivisteAPI"

WORKER_BUILT=0
if [[ "${ORCHIVISTE_DEMO_BUILD_WORKER:-1}" == "1" ]]; then
  build_product "OrchivisteWorker" "OrchivisteWorker"
  WORKER_BUILT=1
fi

API_BINARY="$(find_release_binary "OrchivisteAPI" "OrchivisteAPI")"
ANALYSE_BINARY="$(find_release_binary "OrchivisteAnalyse" "OrchivisteAnalyse")"
WORKER_BINARY="$(find_release_binary "OrchivisteWorker" "OrchivisteWorker" || true)"

if [[ -z "$API_BINARY" || -z "$ANALYSE_BINARY" ]]; then
  echo "Impossible de localiser les binaires release API/Analyse." >&2
  exit 1
fi

mkdir -p \
  "$BIN_DIR" \
  "$LOG_DIR" \
  "$RUN_DIR" \
  "$MODELS_DIR" \
  "$MODELS_SRC_DIR" \
  "$DB_DIR" \
  "$UI_STATE_DIR" \
  "$DATA_INBOX_DIR" \
  "$DATA_ROUTED_DIR" \
  "$DATA_BACKUP_DIR" \
  "$BUNDLE_DIR/resources"

ditto "$ROOT_DIR/OrchivisteAPI/configs" "$CONFIG_DIR"
ditto "$ROOT_DIR/OrchivisteAPI/Resources/Views" "$VIEWS_DIR"

cp -f "$API_BINARY" "$BIN_DIR/OrchivisteAPI"
cp -f "$ANALYSE_BINARY" "$BIN_DIR/OrchivisteAnalyse"
chmod +x "$BIN_DIR/OrchivisteAPI" "$BIN_DIR/OrchivisteAnalyse"

if [[ -n "$WORKER_BINARY" && -f "$WORKER_BINARY" ]]; then
  cp -f "$WORKER_BINARY" "$BIN_DIR/OrchivisteWorker"
  chmod +x "$BIN_DIR/OrchivisteWorker"
fi

ANALYSE_COREML_ENABLED=0
ANALYSE_COREML_MODEL_PATH=""
ANALYSE_COREML_LABELS_PATH=""
ANALYSE_COREML_INPUT_VECTOR="input"
ANALYSE_COREML_OUTPUT_SCORES="var_14"
ANALYSE_COREML_VECTOR_SIZE="256"

PREFERRED_COREML_MODEL="$ROOT_DIR/ml/models-coreml/document_classifier_external.mlpackage"
PREFERRED_COREML_LABELS="$ROOT_DIR/ml/models-src/document_classifier_external.labels.json"
FALLBACK_COREML_MODEL="$ROOT_DIR/ml/models-coreml/tiny_doc_classifier.mlpackage"

if [[ -d "$PREFERRED_COREML_MODEL" ]]; then
  rm -rf "$MODELS_DIR/document_classifier_external.mlpackage"
  ditto "$PREFERRED_COREML_MODEL" "$MODELS_DIR/document_classifier_external.mlpackage"
  ANALYSE_COREML_ENABLED=1
  ANALYSE_COREML_MODEL_PATH="\$KIT_DIR/models-coreml/document_classifier_external.mlpackage"
  if [[ -f "$PREFERRED_COREML_LABELS" ]]; then
    cp -f "$PREFERRED_COREML_LABELS" "$MODELS_SRC_DIR/document_classifier_external.labels.json"
    ANALYSE_COREML_LABELS_PATH="\$KIT_DIR/models-src/document_classifier_external.labels.json"
  fi
elif [[ -d "$FALLBACK_COREML_MODEL" ]]; then
  rm -rf "$MODELS_DIR/tiny_doc_classifier.mlpackage"
  ditto "$FALLBACK_COREML_MODEL" "$MODELS_DIR/tiny_doc_classifier.mlpackage"
  ANALYSE_COREML_ENABLED=1
  ANALYSE_COREML_MODEL_PATH="\$KIT_DIR/models-coreml/tiny_doc_classifier.mlpackage"
fi

write_file "$BUNDLE_DIR/demo.env" <<EOF
KIT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

export ORCHIVISTE_API_HOST=127.0.0.1
export ORCHIVISTE_API_PORT=28780
export ORCHIVISTE_ANALYSE_HOST=127.0.0.1
export ORCHIVISTE_ANALYSE_PORT=28781
export ORCHIVISTE_ANALYSE_URL="http://127.0.0.1:28781"

export ORCHIVISTE_AUTO_MIGRATE=1
export ORCHIVISTE_DB_PROVIDER=sqlite
export ORCHIVISTE_SQLITE_PATH="\$KIT_DIR/state/db/orchiviste.sqlite"
export ORCHIVISTE_CONFIG_DIR="\$KIT_DIR/configs"
export ORCHIVISTE_VIEWS_DIR="\$KIT_DIR/resources/Views"
export ORCHIVISTE_UI_STATE_DIR="\$KIT_DIR/state/ui"

export ORCHIVISTE_LOCAL_INGEST_ROOT="\$KIT_DIR/data/inbox"
export ORCHIVISTE_LOCAL_ROUTE_ROOT="\$KIT_DIR/data/routed"
export ORCHIVISTE_EXPORT_PDFA_ENABLED=0
export ORCHIVISTE_GRAPH_ENABLED=0

export ORCHIVISTE_OCR_ENABLED=1
export ORCHIVISTE_ROUTE_OCR_SEARCHABLE_PDF=1
export ORCHIVISTE_ANALYSE_PROVIDER_APPLE_FM_ENABLED=1
export ORCHIVISTE_ANALYSE_APPLE_TEXT_MAX_CHARS=12000
export ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_ENABLED=$ANALYSE_COREML_ENABLED
export ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_MODEL_PATH="$ANALYSE_COREML_MODEL_PATH"
export ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_INPUT_VECTOR="$ANALYSE_COREML_INPUT_VECTOR"
export ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_OUTPUT_SCORES="$ANALYSE_COREML_OUTPUT_SCORES"
export ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_LABELS_PATH="$ANALYSE_COREML_LABELS_PATH"
export ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_VECTOR_SIZE=$ANALYSE_COREML_VECTOR_SIZE

export ORCHIVISTE_DEMO_START_WORKER=0
export ORCHIVISTE_REDIS_URL=redis://127.0.0.1:6379
EOF

write_file "$CONFIG_DIR/analysis/routing/local.settings.json" <<EOF
{
  "default_name_format" : "{class_code}-{type_doc}-{sujet}-{date}-{numero}",
  "local_route_root" : "$DATA_ROUTED_DIR",
  "default_destination_template" : "Archives/{year}/{class_code}/{type_doc}"
}
EOF

write_file "$BUNDLE_DIR/start-orchiviste.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$KIT_DIR/logs"
RUN_DIR="$KIT_DIR/run"

# shellcheck disable=SC1091
source "$KIT_DIR/demo.env"

mkdir -p \
  "$LOG_DIR" \
  "$RUN_DIR" \
  "$KIT_DIR/state/db" \
  "$KIT_DIR/state/ui" \
  "$KIT_DIR/data/inbox" \
  "$KIT_DIR/data/routed" \
  "$KIT_DIR/data/backups"

is_running() {
  local pidfile="$1"
  [[ -f "$pidfile" ]] || return 1
  local pid
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

start_service() {
  local name="$1"
  local health_url="$2"
  local pidfile="$RUN_DIR/$name.pid"
  local logfile="$LOG_DIR/$name.log"
  local binary="$KIT_DIR/bin/$3"

  if is_running "$pidfile"; then
    echo "$name déjà en cours."
    return 0
  fi

  if [[ ! -x "$binary" ]]; then
    echo "Binaire manquant: $binary" >&2
    return 1
  fi

  nohup /bin/zsh -lc "cd \"$KIT_DIR\" && exec \"$binary\"" >> "$logfile" 2>&1 < /dev/null &
  echo $! > "$pidfile"

  for _ in {1..30}; do
    if curl -fsS "$health_url" >/dev/null 2>&1; then
      echo "$name prêt."
      return 0
    fi
    sleep 1
  done

  echo "Le service $name n'a pas répondu à temps. Voir $logfile" >&2
  return 1
}

start_service "analyse" "http://127.0.0.1:${ORCHIVISTE_ANALYSE_PORT:-28781}/v1/health" "OrchivisteAnalyse"
start_service "api" "http://127.0.0.1:${ORCHIVISTE_API_PORT:-28780}/v1/health" "OrchivisteAPI"

if [[ "${ORCHIVISTE_DEMO_START_WORKER:-0}" == "1" && -x "$KIT_DIR/bin/OrchivisteWorker" ]]; then
  worker_pidfile="$RUN_DIR/worker.pid"
  if ! is_running "$worker_pidfile"; then
    nohup /bin/zsh -lc "cd \"$KIT_DIR\" && exec \"$KIT_DIR/bin/OrchivisteWorker\"" >> "$LOG_DIR/worker.log" 2>&1 < /dev/null &
    echo $! > "$worker_pidfile"
    echo "worker lancé."
  fi
fi

UI_URL="http://127.0.0.1:${ORCHIVISTE_API_PORT:-28780}/ui"
echo
echo "Orchiviste prêt."
echo "UI: $UI_URL"
echo "Logs: $LOG_DIR"
open "$UI_URL" >/dev/null 2>&1 || true
EOF

write_file "$BUNDLE_DIR/stop-orchiviste.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$KIT_DIR/run"

stop_pidfile() {
  local name="$1"
  local pidfile="$RUN_DIR/$name.pid"
  if [[ ! -f "$pidfile" ]]; then
    echo "$name arrêté."
    return 0
  fi
  local pid
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in {1..10}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pidfile"
  echo "$name arrêté."
}

stop_pidfile "worker"
stop_pidfile "api"
stop_pidfile "analyse"
EOF

write_file "$BUNDLE_DIR/status-orchiviste.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$KIT_DIR/run"

service_status() {
  local name="$1"
  local pidfile="$RUN_DIR/$name.pid"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "$name: actif (PID $pid)"
      return 0
    fi
  fi
  echo "$name: arrêté"
}

service_status "analyse"
service_status "api"
service_status "worker"
echo
curl -fsS http://127.0.0.1:28781/v1/health 2>/dev/null && echo "analyse HTTP: ok" || echo "analyse HTTP: indisponible"
curl -fsS http://127.0.0.1:28780/v1/health 2>/dev/null && echo "api HTTP: ok" || echo "api HTTP: indisponible"
EOF

write_file "$BUNDLE_DIR/open-ui.command" <<'EOF'
#!/usr/bin/env bash
open "http://127.0.0.1:28780/ui"
EOF

write_file "$BUNDLE_DIR/start-orchiviste.command" <<'EOF'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/start-orchiviste.sh"
EOF

write_file "$BUNDLE_DIR/stop-orchiviste.command" <<'EOF'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/stop-orchiviste.sh"
EOF

write_file "$BUNDLE_DIR/status-orchiviste.command" <<'EOF'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/status-orchiviste.sh"
EOF

write_file "$BUNDLE_DIR/README.md" <<EOF
# Orchiviste Demo macOS

Ce dossier contient un kit de demonstration natif precompile pour macOS.

## Demarrage rapide

- double-cliquer sur \`start-orchiviste.command\`
- ou lancer \`./start-orchiviste.sh\`
- UI: http://127.0.0.1:28780/ui

## Arret

- \`./stop-orchiviste.sh\`

## Statut

- \`./status-orchiviste.sh\`

## Donnees locales

- base SQLite: \`state/db/orchiviste.sqlite\`
- inbox: \`data/inbox\`
- sortie: \`data/routed\`
- logs: \`logs/\`

## Notes

- le kit utilise les vues et configs copiees au moment du build
- \`FoundationModels\` et \`Vision\` restent des fonctions natives macOS
- le worker est copie dans \`bin/\`, mais le demarrage par defaut reste API + Analyse pour la demo
- Core ML de classification est active par defaut si un modele local est detecte
EOF

chmod +x \
  "$BUNDLE_DIR/start-orchiviste.sh" \
  "$BUNDLE_DIR/stop-orchiviste.sh" \
  "$BUNDLE_DIR/status-orchiviste.sh" \
  "$BUNDLE_DIR/start-orchiviste.command" \
  "$BUNDLE_DIR/stop-orchiviste.command" \
  "$BUNDLE_DIR/status-orchiviste.command" \
  "$BUNDLE_DIR/open-ui.command"

echo
echo "Kit de demonstration genere dans:"
echo "  $BUNDLE_DIR"
if [[ "$WORKER_BUILT" == "1" ]]; then
  echo "Worker release inclus si la compilation a abouti."
fi
