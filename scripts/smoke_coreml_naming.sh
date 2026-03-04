#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_PATH="$ROOT_DIR/ml/models-coreml/tiny_doc_classifier.mlpackage"

if [[ ! -e "$MODEL_PATH" ]]; then
  echo "ECHEC : modèle Core ML introuvable : $MODEL_PATH" >&2
  exit 1
fi

echo "== Test fumée Core ML naming =="
echo "Modele : $MODEL_PATH"

(
  cd "$ROOT_DIR/OrchivisteAnalyse"
  swift test --filter NamingFoundationTests/testCoreMLTinyDocClassifierSmokeLoadsModelAndRanksRules
)

echo "Test fumée Core ML naming réussi."
