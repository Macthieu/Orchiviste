#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SINGLE_SCRIPT="$SCRIPT_DIR/test_pdf_rename.sh"

if [[ ! -x "$SINGLE_SCRIPT" ]]; then
  echo "ERREUR: script introuvable ou non executable: $SINGLE_SCRIPT" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /chemin/fichier.pdf [/chemin/dossier ...]" >&2
  echo "Exemple: $0 ~/Documents/a.pdf ~/Documents/lot-pdf" >&2
  exit 1
fi

collect_pdf_files() {
  local input="$1"
  if [[ -f "$input" ]]; then
    local lower_input
    lower_input="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower_input" == *.pdf ]]; then
      printf '%s\n' "$input"
    fi
    return
  fi

  if [[ -d "$input" ]]; then
    find "$input" -type f \( -iname "*.pdf" \) -print
    return
  fi

  echo "ATTENTION: chemin ignore (introuvable): $input" >&2
}

files=()
while IFS= read -r line; do
  files+=("$line")
done < <(
  for arg in "$@"; do
    collect_pdf_files "$arg"
  done | awk 'NF' | sort -u
)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "ERREUR: aucun PDF trouve dans les chemins fournis." >&2
  exit 1
fi

report_path="${ORCHIVISTE_BATCH_REPORT:-$REPO_ROOT/rename-batch-report-$(date +%Y%m%d-%H%M%S).csv}"
mkdir -p "$(dirname "$report_path")"
echo "file,status,job_id,destination,elapsed_s" >"$report_path"

ok_count=0
ko_count=0
total_count=${#files[@]}

echo "== Test batch renommage PDF =="
echo "Total fichiers: $total_count"
echo "Rapport CSV: $report_path"
echo

for i in "${!files[@]}"; do
  file="${files[$i]}"
  idx=$((i + 1))
  start_ts=$(date +%s)
  tmp_log="$(mktemp)"

  echo "[$idx/$total_count] $file"
  if "$SINGLE_SCRIPT" "$file" >"$tmp_log" 2>&1; then
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    job_id="$(sed -n 's/^job_id=//p' "$tmp_log" | tail -n 1)"
    destination="$(sed -n 's/^Destination locale: //p' "$tmp_log" | tail -n 1)"
    echo "OK  job_id=${job_id:-N/A} (${elapsed}s)"
    printf '"%s",ok,"%s","%s",%s\n' "$file" "${job_id:-}" "${destination:-}" "$elapsed" >>"$report_path"
    ok_count=$((ok_count + 1))
  else
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))
    echo "ECHEC (${elapsed}s)"
    sed -n '1,80p' "$tmp_log" >&2
    printf '"%s",ko,"","",%s\n' "$file" "$elapsed" >>"$report_path"
    ko_count=$((ko_count + 1))
  fi

  rm -f "$tmp_log"
  echo
done

echo "Resume:"
echo "- OK: $ok_count"
echo "- KO: $ko_count"
echo "- Rapport: $report_path"

if [[ $ko_count -gt 0 ]]; then
  exit 1
fi

exit 0
