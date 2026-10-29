#!/usr/bin/env bash
# Bounded foreground wakeup probe under two-core CPU pressure.
# This is a scheduler/UI responsiveness proxy, not a browser paint benchmark.
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
source "$root/common.sh"

usage() {
  echo "Usage: $0 [OUTPUT_DIR] [SECONDS] [WORKERS]" >&2
}
[[ "${EUID}" -ne 0 ]] || { echo 'Run without sudo; privileged data is best-effort.' >&2; exit 2; }
out=${1:-"$HOME/mbp51-bench/ui-load-$(uname -r)-$(date +%Y%m%d-%H%M%S)"}
duration=${2:-30}
workers=${3:-2}
[[ "$duration" =~ ^[1-9][0-9]*$ && "$workers" =~ ^[1-9][0-9]*$ ]] || { usage; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo 'python3 is required for percentile calculation' >&2; exit 2; }
mkdir -p "$out"
capture_metadata "$out"
write_sample_header "$out/samples.csv"
append_sample "$out/samples.csv" before

pids=()
cleanup() {
  local pid
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM
for ((i = 1; i <= workers; i++)); do
  yes > /dev/null &
  pids+=("$!")
done

python3 - "$duration" "$out/latency_us.csv" > "$out/summary.env" <<'PY'
import math
import statistics
import sys
import time

duration = float(sys.argv[1])
path = sys.argv[2]
period = 0.005
deadline = time.monotonic() + duration
values = []
next_tick = time.monotonic() + period
while time.monotonic() < deadline:
    time.sleep(max(0.0, next_tick - time.monotonic()))
    now = time.monotonic()
    values.append(max(0.0, (now - next_tick) * 1_000_000.0))
    next_tick += period

values.sort()
def percentile(p):
    if not values:
        return 0.0
    return values[min(len(values) - 1, max(0, math.ceil(p * len(values)) - 1))]

with open(path, "w", encoding="utf-8") as handle:
    handle.write("sample,overshoot_us\n")
    for index, value in enumerate(values, 1):
        handle.write(f"{index},{value:.3f}\n")

print(f"duration_s={duration}")
print(f"latency_samples={len(values)}")
print(f"latency_mean_us={statistics.mean(values) if values else 0.0:.3f}")
print(f"latency_p50_us={percentile(0.50):.3f}")
print(f"latency_p95_us={percentile(0.95):.3f}")
print(f"latency_p99_us={percentile(0.99):.3f}")
PY
printf 'workers=%s\n' "$workers" >> "$out/summary.env"
append_sample "$out/samples.csv" after
cp "$out/summary.env" "$out/summary.txt"
echo "Foreground latency proxy captured: $out"
