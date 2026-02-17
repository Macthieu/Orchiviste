#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== Validation release Orchiviste =="
cd "$ROOT_DIR"

./scripts/dev_up.sh "$@"
./scripts/smoke_mvp.sh
./scripts/smoke_webhook_hmac.sh

echo
echo "Validation release réussie."
