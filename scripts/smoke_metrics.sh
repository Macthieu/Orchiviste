#!/usr/bin/env bash
set -euo pipefail

API_BASE="${ORCHIVISTE_API_BASE:-http://127.0.0.1:28780}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Commande requise manquante : $cmd" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd python3

echo "== Test fumée métriques API Orchiviste =="
echo "API : $API_BASE"

# Génère quelques requêtes pour alimenter les compteurs.
curl -sS -f "$API_BASE/v1/health" >/dev/null
curl -sS "$API_BASE/v1/jobs/00000000-0000-0000-0000-000000000000" >/dev/null || true

metrics_file="$TMP_DIR/metrics.json"
status_code="$(curl -sS -o "$metrics_file" -w "%{http_code}" "$API_BASE/v1/metrics")"
if [[ "$status_code" != "200" ]]; then
  echo "ÉCHEC : /v1/metrics HTTP $status_code" >&2
  cat "$metrics_file" >&2 || true
  exit 1
fi

python3 - "$metrics_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

required_keys = [
    "started_at",
    "uptime_s",
    "total_requests",
    "in_flight",
    "by_status",
    "by_method",
    "top_routes",
    "latency_ms",
]
missing = [k for k in required_keys if k not in payload]
if missing:
    print("ÉCHEC : clés manquantes:", ", ".join(missing))
    sys.exit(1)

if not isinstance(payload.get("total_requests"), int) or payload["total_requests"] < 1:
    print("ÉCHEC : total_requests invalide")
    sys.exit(1)

latency = payload.get("latency_ms", {})
if not isinstance(latency, dict) or "avg" not in latency or "max" not in latency:
    print("ÉCHEC : bloc latency_ms invalide")
    sys.exit(1)

print("OK  endpoint /v1/metrics")
print(f"OK  total_requests={payload['total_requests']}")
PY

echo "Test fumée métriques réussi."
