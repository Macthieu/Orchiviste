#!/usr/bin/env bash
set -euo pipefail

API_BASE="${ORCHIVISTE_API_BASE:-http://127.0.0.1:28780}"
OPENAPI_URL="${API_BASE%/}/v1/openapi.json"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

echo "== Vérification OpenAPI MVP =="
echo "Source: $OPENAPI_URL"

if ! curl -fsS "$OPENAPI_URL" -o "$tmp_file"; then
  echo "ERREUR: impossible de lire $OPENAPI_URL" >&2
  exit 1
fi

python3 - "$tmp_file" <<'PY'
import json
import sys

doc_path = sys.argv[1]
with open(doc_path, "r", encoding="utf-8") as f:
    spec = json.load(f)

required_paths = {
    "/v1/ingest": ["post"],
    "/v1/jobs/{id}": ["get"],
    "/v1/jobs/{id}/cancel": ["post"],
    "/v1/workers/enroll": ["post"],
    "/v1/workers/{id}/approve": ["post"],
    "/v1/workers/{id}/heartbeat": ["post"],
    "/v1/presets": ["get", "post"],
    "/v1/analyse": ["post"],
    "/v1/preview/{id}/thumbnail": ["get"],
    "/v1/preview/{id}/page/{n}.jpg": ["get"],
    "/v1/preview/{id}/text": ["get"],
    "/v1/preview/{id}/office": ["get"],
    "/v1/openapi.json": ["get"],
    "/v1/metrics": ["get"],
    "/v1/events": ["get"],
    "/v1/route/{file_id}": ["post"],
}

errors = []
openapi = str(spec.get("openapi", ""))
if not openapi.startswith("3.1"):
    errors.append(f"version OpenAPI invalide: {openapi!r} (attendu 3.1.x)")
else:
    print(f"OK  version OpenAPI: {openapi}")

paths = spec.get("paths", {})
if not isinstance(paths, dict):
    errors.append("champ 'paths' absent ou invalide")
    paths = {}

for path, methods in required_paths.items():
    node = paths.get(path)
    if not isinstance(node, dict):
        errors.append(f"path manquant: {path}")
        continue
    for method in methods:
        if method not in node:
            errors.append(f"methode manquante: {method.upper()} {path}")
        else:
            print(f"OK  {method.upper():<4} {path}")

webhooks = spec.get("webhooks", {})
if not isinstance(webhooks, dict):
    errors.append("champ 'webhooks' absent ou invalide")
    webhooks = {}

event_delivered = webhooks.get("eventDelivered")
if not isinstance(event_delivered, dict) or "post" not in event_delivered:
    errors.append("webhook 'eventDelivered.post' manquant")
else:
    post = event_delivered["post"]
    print("OK  webhook eventDelivered.post")
    params = post.get("parameters", [])
    if not isinstance(params, list):
        errors.append("parameters du webhook invalides")
        params = []
    names = {str(p.get("name", "")).lower() for p in params if isinstance(p, dict)}
    for header in ("x-orchiviste-signature", "x-orchiviste-timestamp"):
        if header not in names:
            errors.append(f"header webhook manquant: {header}")
        else:
            print(f"OK  header webhook: {header}")

if errors:
    print("")
    print("ERREURS OpenAPI MVP détectées:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)

print("")
print("Vérification OpenAPI MVP réussie.")
PY
