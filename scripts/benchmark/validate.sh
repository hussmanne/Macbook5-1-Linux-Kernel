#!/usr/bin/env bash
# Validate a captured benchmark directory; never runs a workload.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "Usage: $0 REPORT_DIR" >&2; exit 2; }
dir=$1
[[ -s "$dir/metadata.txt" ]] || { echo 'Missing metadata.txt' >&2; exit 1; }
for key in captured_at kernel_release cmdline cpu_model config_sha256; do
  grep -Eq "^${key}=" "$dir/metadata.txt" || { echo "Missing metadata key: $key" >&2; exit 1; }
done
if [[ -e "$dir/samples.csv" ]]; then
  [[ "$(sed -n '1p' "$dir/samples.csv")" == \
    'captured_at,sample,load1,context_switches,memory_psi_some_avg10,cpu_temp_max_mC,fan_rpm_max,battery_power_now_uW,ac_online,cpu0_idle_time_us' ]] || {
      echo 'Unexpected samples.csv header' >&2; exit 1;
    }
  [[ "$(wc -l < "$dir/samples.csv")" -ge 2 ]] || { echo 'samples.csv has no samples' >&2; exit 1; }
fi
if [[ -e "$dir/summary.env" ]]; then
  for key in duration_s latency_samples latency_p50_us latency_p95_us latency_p99_us workers; do
    grep -Eq "^${key}=" "$dir/summary.env" || { echo "Missing summary key: $key" >&2; exit 1; }
  done
  [[ -s "$dir/latency_us.csv" ]] || { echo 'Missing latency_us.csv' >&2; exit 1; }
fi
echo "Benchmark report validated: $dir"
