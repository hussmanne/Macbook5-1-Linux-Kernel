#!/usr/bin/env bash
# Capture a repeatable, read-only idle baseline on the physical MacBook.
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
source "$root/common.sh"

usage() {
  echo "Usage: $0 [OUTPUT_DIR] [SAMPLES] [INTERVAL_SECONDS]" >&2
}
[[ "${EUID}" -ne 0 ]] || { echo 'Run without sudo; privileged data is best-effort.' >&2; exit 2; }
out=${1:-"$HOME/mbp51-bench/baseline-$(uname -r)-$(date +%Y%m%d-%H%M%S)"}
samples=${2:-5}
interval=${3:-5}
[[ "$samples" =~ ^[1-9][0-9]*$ && "$interval" =~ ^[1-9][0-9]*([.][0-9]+)?$ ]] || { usage; exit 2; }
mkdir -p "$out"
capture_metadata "$out"
write_sample_header "$out/samples.csv"
for ((i = 1; i <= samples; i++)); do
  append_sample "$out/samples.csv" "$i"
  (( i < samples )) && sleep "$interval"
done
cat > "$out/README.txt" <<EOF
Read-only idle baseline captured by scripts/benchmark/baseline.sh.
Kernel: $(uname -r)
Samples: $samples
Interval seconds: $interval
This is evidence only; it does not apply PowerTOP, switch GPUs, suspend, or change boot state.
EOF
echo "Baseline captured: $out"
