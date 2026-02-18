#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_WEBHOOK="1"
SKIP_UP="0"
run_pdf_batch="0"
start_epoch="$(date +%s)"

dev_up_args=()
pdf_inputs=()

usage() {
  cat <<'EOF'
Usage: ./scripts/preflight_local.sh [options]

Modes:
  --full            validation complète (défaut) : smoke + webhook + openapi
  --quick           validation rapide : smoke + openapi (sans webhook)

Options:
  --skip-up         n'exécute pas ./scripts/dev_up.sh (stack déjà démarrée)
  --pdf <path>      lance aussi le test batch de renommage sur fichier/dossier PDF
                    option répétable, ex: --pdf ~/Documents --pdf ~/a.pdf
  --build           transmis à dev_up.sh
  --no-build        transmis à dev_up.sh
  --classic-builder transmis à dev_up.sh
  --anon-auth       transmis à dev_up.sh
  --help            affiche cette aide
EOF
}

while (($# > 0)); do
  case "$1" in
    --full)
      RUN_WEBHOOK="1"
      ;;
    --quick)
      RUN_WEBHOOK="0"
      ;;
    --skip-up)
      SKIP_UP="1"
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
    --build|--no-build|--classic-builder|--anon-auth)
      dev_up_args+=("$1")
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
  echo "INFO: démarrage stack ignoré (--skip-up)."
else
  ./scripts/dev_up.sh "${dev_up_args[@]}"
fi

./scripts/check_openapi_mvp.sh
./scripts/smoke_mvp.sh

if [[ "$RUN_WEBHOOK" == "1" ]]; then
  ./scripts/smoke_webhook_hmac.sh
else
  echo "INFO: test webhook ignoré (--quick)."
fi

if [[ "$run_pdf_batch" == "1" ]]; then
  ./scripts/test_pdf_rename_batch.sh "${pdf_inputs[@]}"
fi

elapsed=$(( $(date +%s) - start_epoch ))
echo
echo "Préflight local réussi en ${elapsed}s."
