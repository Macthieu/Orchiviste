#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

ANALYSE_PORT="${ORCHIVISTE_ANALYSE_REGRESSION_PORT:-}"
FIXTURES_DIR="${ORCHIVISTE_ANALYSE_REGRESSION_FIXTURES:-$ROOT_DIR/fixtures/regression/analyse}"
ANALYSE_LOG="$TMP_DIR/analyse.log"

cleanup() {
  if [[ -n "${ANALYSE_PID:-}" ]]; then
    kill "$ANALYSE_PID" >/dev/null 2>&1 || true
    wait "$ANALYSE_PID" >/dev/null 2>&1 || true
  fi
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

pick_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

need_cmd curl
need_cmd python3

if [[ -z "$ANALYSE_PORT" ]]; then
  ANALYSE_PORT="$(pick_port)"
fi

if [[ ! -d "$FIXTURES_DIR" ]]; then
  echo "Dossier de fixtures introuvable : $FIXTURES_DIR" >&2
  exit 1
fi

echo "== Dataset de régression Analyse =="
echo "Port Analyse : $ANALYSE_PORT"
echo "Fixtures     : $FIXTURES_DIR"

(
  cd "$ROOT_DIR/OrchivisteAnalyse"
  ORCHIVISTE_ANALYSE_HOST=127.0.0.1 \
  ORCHIVISTE_ANALYSE_PORT="$ANALYSE_PORT" \
  ./.build/debug/OrchivisteAnalyse >"$ANALYSE_LOG" 2>&1
) &
ANALYSE_PID=$!

for _ in $(seq 1 60); do
  if ! kill -0 "$ANALYSE_PID" >/dev/null 2>&1; then
    echo "ECHEC : OrchivisteAnalyse s'est arrêté pendant le dataset de régression." >&2
    tail -n 120 "$ANALYSE_LOG" >&2 || true
    exit 1
  fi
  if curl -sS "http://127.0.0.1:$ANALYSE_PORT/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

python3 - "$ANALYSE_PORT" "$FIXTURES_DIR" <<'PY'
import glob
import json
import sys
import urllib.request

port = int(sys.argv[1])
fixtures_dir = sys.argv[2]
fixture_paths = sorted(glob.glob(f"{fixtures_dir}/*.json"))
if not fixture_paths:
    print(f"ECHEC : aucune fixture JSON dans {fixtures_dir}", file=sys.stderr)
    sys.exit(1)

def post_json(url: str, payload: dict) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status}")
        return json.loads(resp.read().decode("utf-8"))

for fixture_path in fixture_paths:
    with open(fixture_path, "r", encoding="utf-8") as f:
        fixture = json.load(f)
    name = fixture.get("name") or fixture_path
    request_payload = fixture.get("request") or {}
    expect = fixture.get("expect") or {}

    response = post_json(f"http://127.0.0.1:{port}/v1/analyse", request_payload)
    review = response.get("review") or {}
    capture = response.get("capture") or {}

    if "type_doc" in expect and response.get("type_doc") != expect["type_doc"]:
        raise SystemExit(f"ECHEC [{name}] type_doc attendu={expect['type_doc']} reçu={response.get('type_doc')}")

    if "suggested_class_code" in expect and response.get("suggested_class_code") != expect["suggested_class_code"]:
        raise SystemExit(
            f"ECHEC [{name}] suggested_class_code attendu={expect['suggested_class_code']} "
            f"reçu={response.get('suggested_class_code')}"
        )

    if "needs_review" in expect:
        actual_review = bool(review.get("needs_review"))
        if actual_review != bool(expect["needs_review"]):
            raise SystemExit(f"ECHEC [{name}] needs_review attendu={expect['needs_review']} reçu={actual_review}")

    reasons_any = expect.get("reasons_any") or []
    if reasons_any:
        actual_reasons = set(review.get("reasons") or [])
        if not actual_reasons.intersection(reasons_any):
            raise SystemExit(
                f"ECHEC [{name}] aucune raison attendue trouvée. attendu∩reçu vide pour {reasons_any} / {sorted(actual_reasons)}"
            )

    field_keys_all = expect.get("field_keys_all") or []
    actual_fields = response.get("champs") or {}
    missing_fields = [key for key in field_keys_all if key not in actual_fields]
    if missing_fields:
        raise SystemExit(f"ECHEC [{name}] champs manquants: {', '.join(missing_fields)}")

    capture_unit_count_min = int(expect.get("capture_unit_count_min") or 0)
    actual_unit_count = int(capture.get("unit_count") or 0)
    if actual_unit_count < capture_unit_count_min:
        raise SystemExit(
            f"ECHEC [{name}] capture.unit_count attendu>={capture_unit_count_min} reçu={actual_unit_count}"
        )

    print(f"OK  {name}")

print(f"Dataset de regression valide sur {len(fixture_paths)} fixture(s).")
PY

echo "Dataset de régression réussi."
