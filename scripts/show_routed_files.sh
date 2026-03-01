#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_DIR="${ORCHIVISTE_ROUTED_EXPORT_DIR:-$REPO_ROOT/runtime/routed}"
LIMIT="${1:-40}"

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [nombre_fichiers]" >&2
  exit 1
fi

echo "Racine hôte des fichiers routés : $HOST_DIR"
if [[ ! -d "$HOST_DIR" ]]; then
  echo "Dossier introuvable."
  exit 0
fi

echo
echo "Derniers fichiers traités :"
find "$HOST_DIR" -type f -print0 \
  | xargs -0 stat -f "%m|%Sm|%N" -t "%Y-%m-%d %H:%M:%S" \
  | sort -t "|" -k1,1nr \
  | head -n "$LIMIT" \
  | awk -F"|" '{print $2 "  " $3}'
