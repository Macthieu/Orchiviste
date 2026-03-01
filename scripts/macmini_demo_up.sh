#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/deploy/mac-mini/orchiviste.macmini.env"

resolve_path() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    return 1
  fi
  if [[ "$raw" == /* ]]; then
    printf '%s\n' "$raw"
  else
    printf '%s\n' "$ROOT_DIR/${raw#./}"
  fi
}

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

mkdir -p \
  "$(resolve_path "${ORCHIVISTE_INBOX_EXPORT_DIR:-./runtime/inbox}")" \
  "$(resolve_path "${ORCHIVISTE_ROUTED_EXPORT_DIR:-./runtime/routed}")" \
  "$(resolve_path "${ORCHIVISTE_MACMINI_BACKUP_DIR:-./runtime/backups}")"

cd "$ROOT_DIR"
./scripts/dev_up.sh "$@"
