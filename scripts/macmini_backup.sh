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

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Commande requise manquante : $cmd" >&2
    exit 1
  fi
}

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

need_cmd docker

backup_root="$(resolve_path "${ORCHIVISTE_MACMINI_BACKUP_DIR:-./runtime/backups}")"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$backup_root/$timestamp"
mkdir -p "$backup_dir"

cp -R "$ROOT_DIR/OrchivisteAPI/configs" "$backup_dir/configs"

if [[ -f "$ENV_FILE" ]]; then
  cp "$ENV_FILE" "$backup_dir/orchiviste.macmini.env"
fi

inbox_dir="$(resolve_path "${ORCHIVISTE_INBOX_EXPORT_DIR:-./runtime/inbox}")"
routed_dir="$(resolve_path "${ORCHIVISTE_ROUTED_EXPORT_DIR:-./runtime/routed}")"

if [[ -d "$inbox_dir" ]]; then
  cp -R "$inbox_dir" "$backup_dir/inbox"
fi
if [[ -d "$routed_dir" ]]; then
  cp -R "$routed_dir" "$backup_dir/routed"
fi

if docker volume inspect orchiviste_sqlite_data >/dev/null 2>&1; then
  docker run --rm \
    -v orchiviste_sqlite_data:/from \
    -v "$backup_dir:/to" \
    alpine:3.20 \
    sh -c 'cd /from && tar -czf /to/orchiviste_sqlite_data.tgz .'
else
  echo "INFO: volume Docker orchiviste_sqlite_data absent, archive SQLite ignorée."
fi

echo "Backup Mac mini créé : $backup_dir"
