#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_DIR="$ROOT_DIR/OrchivisteAPI"
TMP_DIR_RAW="$(mktemp -d "${TMPDIR:-/tmp}/orchiviste-muni-store-activation-XXXXXX")"
TMP_DIR="$(cd "$TMP_DIR_RAW" && pwd -P)"

API_HOST="${ORCHIVISTE_MUNI_STORE_SMOKE_HOST:-127.0.0.1}"
API_PORT="${ORCHIVISTE_MUNI_STORE_SMOKE_PORT:-}"
SKIP_BUILD="${ORCHIVISTE_MUNI_STORE_SMOKE_SKIP_BUILD:-0}"
KEEP_TMP="${ORCHIVISTE_MUNI_STORE_SMOKE_KEEP_TMP:-0}"

API_LOG="$TMP_DIR/orchiviste-api.log"
SQLITE_PATH="$TMP_DIR/orchiviste-smoke.sqlite"
COCKPIT_CONFIG="$TMP_DIR/cockpit.config.json"
STUB_TOOL="$TMP_DIR/muni-store-smoke-cli.sh"
RESPONSES_DIR="$TMP_DIR/responses"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Commande requise manquante: $cmd" >&2
    exit 1
  fi
}

pick_port() {
  python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

cleanup() {
  if [[ -n "${API_PID:-}" ]]; then
    kill "$API_PID" >/dev/null 2>&1 || true
    wait "$API_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_TMP" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "Runtime conserve: $TMP_DIR"
  fi
}
trap cleanup EXIT

assert_http_code() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  local file="${4:-}"
  if [[ "$actual" != "$expected" ]]; then
    echo "ECHEC [$label] HTTP attendu $expected, recu $actual" >&2
    if [[ -n "$file" && -f "$file" ]]; then
      cat "$file" >&2
    fi
    if [[ -f "$API_LOG" ]]; then
      echo "--- OrchivisteAPI log ---" >&2
      tail -n 120 "$API_LOG" >&2 || true
    fi
    exit 1
  fi
}

assert_redirect_to_store() {
  local headers="$1"
  local label="$2"
  python3 - "$headers" "$label" <<'PY'
import sys

headers_path, label = sys.argv[1:3]
location = ""
with open(headers_path, "r", encoding="utf-8", errors="replace") as handle:
    for line in handle:
        if line.lower().startswith("location:"):
            location = line.split(":", 1)[1].strip()

if not location.startswith("/ui/muni/store?notice="):
    raise SystemExit(f"ECHEC [{label}] redirect inattendu: {location}")
print(f"OK  {label}: redirect store")
PY
}

assert_store_state() {
  local file="$1"
  local module="$2"
  local state="$3"
  local state_class="$4"
  local expected_action_url="$5"
  local label="$6"
  python3 - "$file" "$module" "$state" "$state_class" "$expected_action_url" "$label" <<'PY'
import re
import sys
from html import unescape

file_path, module, state, state_class, expected_action_url, label = sys.argv[1:7]
html = open(file_path, encoding="utf-8").read()
visible_text = unescape(re.sub(r"<[^>]+>", " ", html)).lower()

if "installer" in visible_text or "retirer" in visible_text:
    raise SystemExit(f"ECHEC [{label}] action installation/retrait detectee")

pattern = (
    r'<article class="module-card">'
    r'(?:(?!</article>).)*?<h2>' + re.escape(module) + r'</h2>'
    r'(?:(?!</article>).)*?</article>'
)
match = re.search(pattern, html, re.S)
if not match:
    raise SystemExit(f"ECHEC [{label}] carte absente: {module}")

card = unescape(match.group(0))
expected_badge = f'<span class="badge {state_class}">{state}</span>'
if expected_badge not in card:
    raise SystemExit(f"ECHEC [{label}] etat attendu absent: {expected_badge}")

if expected_action_url not in card:
    raise SystemExit(f"ECHEC [{label}] action attendue absente: {expected_action_url}")

print(f"OK  {label}: {module} affiche {state}")
PY
}

need_cmd curl
need_cmd python3
if [[ "$SKIP_BUILD" != "1" ]]; then
  need_cmd swift
fi

if [[ -z "$API_PORT" ]]; then
  API_PORT="$(pick_port)"
fi
BASE_URL="http://${API_HOST}:${API_PORT}"

mkdir -p "$RESPONSES_DIR"

cat > "$STUB_TOOL" <<'SH'
#!/usr/bin/env bash
echo "Muni store smoke stub"
SH
chmod +x "$STUB_TOOL"

cat > "$COCKPIT_CONFIG" <<JSON
{
  "schema_version": "1.0",
  "workspace_path": "$ROOT_DIR/..",
  "runtime_directory": "$TMP_DIR/cockpit-runtime",
  "requests_directory": "requests",
  "results_directory": "results",
  "history_file": "history.jsonl",
  "tool_timeout_seconds": 30,
  "tools": [
    {
      "id": "MuniRenommage",
      "display_name": "MuniRenommage",
      "mission": "Smoke cible activation locale App Store Muni.",
      "executable": "muni-store-smoke-cli",
      "executable_path": "$STUB_TOOL",
      "version": "0.0.1",
      "integration_status": "ready",
      "capabilities": ["preview", "apply", "canonical-run"],
      "default_action": "preview",
      "default_parameters": {},
      "supports_dry_run": true,
      "destructive_requires_confirmation": true,
      "confirmation_parameter": "confirm_apply",
      "enabled": true
    }
  ]
}
JSON

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "== Build OrchivisteAPI =="
  (cd "$API_DIR" && swift build -c debug --product OrchivisteAPI)
fi

echo "== Demarrage OrchivisteAPI =="
(
  cd "$API_DIR"
  ORCHIVISTE_API_HOST="$API_HOST" \
  ORCHIVISTE_API_PORT="$API_PORT" \
  ORCHIVISTE_AUTO_MIGRATE=1 \
  ORCHIVISTE_SQLITE_PATH="$SQLITE_PATH" \
  ORCHIVISTE_COCKPIT_CONFIG_FILE="$COCKPIT_CONFIG" \
  ./.build/debug/OrchivisteAPI >"$API_LOG" 2>&1
) &
API_PID=$!

for _ in $(seq 1 60); do
  if ! kill -0 "$API_PID" >/dev/null 2>&1; then
    echo "ECHEC: OrchivisteAPI arrete avant readiness." >&2
    tail -n 120 "$API_LOG" >&2 || true
    exit 1
  fi
  if curl -sS "$BASE_URL/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "== Scenario S7.8: desactiver puis reactiver un module Muni connu =="
INITIAL_STORE="$RESPONSES_DIR/01-store-initial.html"
INITIAL_CODE="$(curl -sS -o "$INITIAL_STORE" -w "%{http_code}" "$BASE_URL/ui/muni/store")"
assert_http_code "$INITIAL_CODE" "200" "store.initial" "$INITIAL_STORE"
assert_store_state \
  "$INITIAL_STORE" \
  "MuniRenommage" \
  "active" \
  "state-active" \
  "/ui/muni/store/apps/MuniRenommage/deactivate" \
  "store.initial"

DEACTIVATE_HEADERS="$RESPONSES_DIR/02-deactivate.headers"
DEACTIVATE_BODY="$RESPONSES_DIR/02-deactivate.html"
DEACTIVATE_CODE="$(curl -sS -D "$DEACTIVATE_HEADERS" -o "$DEACTIVATE_BODY" -w "%{http_code}" \
  -X POST "$BASE_URL/ui/muni/store/apps/MuniRenommage/deactivate")"
assert_http_code "$DEACTIVATE_CODE" "303" "store.deactivate" "$DEACTIVATE_BODY"
assert_redirect_to_store "$DEACTIVATE_HEADERS" "store.deactivate"

DISABLED_STORE="$RESPONSES_DIR/03-store-disabled.html"
DISABLED_CODE="$(curl -sS -o "$DISABLED_STORE" -w "%{http_code}" "$BASE_URL/ui/muni/store")"
assert_http_code "$DISABLED_CODE" "200" "store.disabled" "$DISABLED_STORE"
assert_store_state \
  "$DISABLED_STORE" \
  "MuniRenommage" \
  "desactive" \
  "state-disabled" \
  "/ui/muni/store/apps/MuniRenommage/activate" \
  "store.disabled"

ACTIVATE_HEADERS="$RESPONSES_DIR/04-activate.headers"
ACTIVATE_BODY="$RESPONSES_DIR/04-activate.html"
ACTIVATE_CODE="$(curl -sS -D "$ACTIVATE_HEADERS" -o "$ACTIVATE_BODY" -w "%{http_code}" \
  -X POST "$BASE_URL/ui/muni/store/apps/MuniRenommage/activate")"
assert_http_code "$ACTIVATE_CODE" "303" "store.activate" "$ACTIVATE_BODY"
assert_redirect_to_store "$ACTIVATE_HEADERS" "store.activate"

ENABLED_STORE="$RESPONSES_DIR/05-store-enabled.html"
ENABLED_CODE="$(curl -sS -o "$ENABLED_STORE" -w "%{http_code}" "$BASE_URL/ui/muni/store")"
assert_http_code "$ENABLED_CODE" "200" "store.enabled" "$ENABLED_STORE"
assert_store_state \
  "$ENABLED_STORE" \
  "MuniRenommage" \
  "active" \
  "state-active" \
  "/ui/muni/store/apps/MuniRenommage/deactivate" \
  "store.enabled"

echo
echo "Smoke App Store Muni activation locale: SUCCES"
echo " - store initial: active"
echo " - apres desactivation: desactive"
echo " - apres reactivation: active"
echo " - aucune action installation/retrait exposee"
