#!/usr/bin/env bash
# Compare two harness directories without modifying either input.
set -euo pipefail

usage() { echo "Usage: $0 BEFORE_DIR AFTER_DIR [REPORT_FILE]" >&2; }
[[ $# -ge 2 && $# -le 3 ]] || { usage; exit 2; }
before=$1
after=$2
report=${3:-"$after/compare.txt"}
for dir in "$before" "$after"; do
  [[ -s "$dir/metadata.txt" ]] || { echo "Missing metadata.txt: $dir" >&2; exit 1; }
done
get_value() {
  local file=$1 key=$2
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}
percent_delta() {
  awk -v a="$1" -v b="$2" 'BEGIN { if (a == 0) { print "n/a" } else { printf "%.2f%%", ((b-a)/a)*100 } }'
}
{
  echo "MacBookPro5,1 benchmark comparison"
  echo "before=$before"
  echo "after=$after"
  echo
  echo "=== Identity (must be reviewed before comparing) ==="
  printf 'before kernel: %s\n' "$(get_value "$before/metadata.txt" kernel_release)"
  printf 'after kernel:  %s\n' "$(get_value "$after/metadata.txt" kernel_release)"
  printf 'before source: %s\n' "$(get_value "$before/metadata.txt" source_sha)"
  printf 'after source:  %s\n' "$(get_value "$after/metadata.txt" source_sha)"
  printf 'before config: %s\n' "$(get_value "$before/metadata.txt" config_sha256)"
  printf 'after config:  %s\n' "$(get_value "$after/metadata.txt" config_sha256)"
  echo
  if [[ -s "$before/summary.env" && -s "$after/summary.env" ]]; then
    echo "=== Foreground wakeup latency proxy ==="
    for key in latency_p50_us latency_p95_us latency_p99_us; do
      a=$(get_value "$before/summary.env" "$key")
      b=$(get_value "$after/summary.env" "$key")
      printf '%s: before=%s after=%s delta=%s\n' "$key" "$a" "$b" "$(percent_delta "$a" "$b")"
    done
    echo 'Interpretation: lower is better; this is not a browser paint/input measurement.'
  else
    echo 'No paired summary.env files; compare samples.csv and workload metadata manually.'
  fi
  echo
  echo '=== Review gates ==='
  echo 'Keep only when the workload, AC/battery state, thermal state, source and config are comparable.'
  echo 'Record KEEP / REVERT / NEEDS EVIDENCE outside this generated report.'
} | tee "$report"
