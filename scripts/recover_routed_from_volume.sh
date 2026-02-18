#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="${1:-$REPO_ROOT/runtime/routed-recovered}"
VOLUME_NAME="${ORCHIVISTE_SQLITE_VOLUME:-orchiviste_orchiviste_sqlite_data}"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERREUR: docker n'est pas installe ou non accessible." >&2
  exit 1
fi

if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  echo "ERREUR: volume docker introuvable: $VOLUME_NAME" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
ABS_TARGET="$(cd "$TARGET_DIR" && pwd)"

echo "Volume source: $VOLUME_NAME"
echo "Destination hote: $ABS_TARGET"
echo "Copie des PDF routés historiques..."

docker run --rm \
  -v "$VOLUME_NAME:/source:ro" \
  -v "$ABS_TARGET:/target" \
  --entrypoint sh redis:7-alpine -lc '
    mkdir -p /target
    if [ ! -d /source/routed ]; then
      echo "Aucun dossier /source/routed dans le volume."
      exit 0
    fi
    cp -R /source/routed/. /target/
    count=$(find /target -type f -name "*.pdf" | wc -l | tr -d " ")
    echo "PDF recuperes: ${count}"
    echo "Exemples:"
    find /target -type f -name "*.pdf" | head -n 10
  '

echo
echo "Termine. Tu peux ouvrir:"
echo "$ABS_TARGET"
