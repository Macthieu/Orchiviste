#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== Validation release Orchiviste =="
cd "$ROOT_DIR"
./scripts/preflight_local.sh --full "$@"
