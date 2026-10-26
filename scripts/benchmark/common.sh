#!/usr/bin/env bash
# Shared, read-only measurement helpers for the MacBookPro5,1 harness.
set -euo pipefail

benchmark_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

read_first_line() {
  local file=$1
  if [[ -r "$file" ]]; then
    IFS= read -r line < "$file" || true
    printf '%s' "$line"
  fi
  return 0
}

sum_sysfs_glob() {
  local pattern=$1 file value total=0
  shopt -s nullglob
  for file in $pattern; do
    [[ -r "$file" ]] || continue
    value=$(<"$file")
    [[ "$value" =~ ^[0-9]+$ ]] || continue
    total=$((total + value))
  done
  printf '%s' "$total"
}

max_sysfs_glob() {
  local pattern=$1 file value max=0
  shopt -s nullglob
  for file in $pattern; do
    [[ -r "$file" ]] || continue
    value=$(<"$file")
    [[ "$value" =~ ^[0-9]+$ ]] || continue
    if (( value > max )); then max=$value; fi
  done
  printf '%s' "$max"
}

memory_psi_avg10() {
  local token
  [[ -r /proc/pressure/memory ]] || return 0
  while read -r token; do
    case "$token" in
      avg10=*) printf '%s' "${token#avg10=}"; return 0 ;;
    esac
  done < <(awk '$1 == "some" { for (i = 2; i <= NF; i++) print $i }' /proc/pressure/memory)
}

cpu_context_switches() {
  awk '$1 == "ctxt" { print $2; exit }' /proc/stat
}

capture_metadata() {
  local out=$1 repo_root=${2:-$(benchmark_repo_root)} config_file config_hash microcode
  mkdir -p "$out"
  {
    printf 'captured_at=%s\n' "$(date -Iseconds)"
    printf 'kernel_release=%s\n' "$(uname -r)"
    printf 'kernel_uname=%s\n' "$(uname -a)"
    printf 'cmdline=%s\n' "$(read_first_line /proc/cmdline)"
    printf 'arch=%s\n' "$(uname -m)"
    printf 'cpu_model=%s\n' "$(awk -F: '$1 == "model name" { sub(/^[[:space:]]+/, "", $2); print $2; exit }' /proc/cpuinfo)"
    printf 'cpu_count=%s\n' "$(nproc 2>/dev/null || true)"
    printf 'ac_online=%s\n' "$(read_first_line /sys/class/power_supply/ADP1/online)"
    printf 'battery_capacity=%s\n' "$(read_first_line /sys/class/power_supply/BAT0/capacity)"
    printf 'governor=%s\n' "$(read_first_line /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    printf 'min_freq=%s\n' "$(read_first_line /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq)"
    printf 'max_freq=%s\n' "$(read_first_line /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)"
    microcode=$(read_first_line /sys/devices/system/cpu/microcode/version || true)
    printf 'microcode=%s\n' "$microcode"
    if [[ -r "$repo_root/source.lock" ]]; then
      awk -F= '/^(SOURCE_SHA|SOURCE_ARCHIVE_SHA256)=/ { print tolower($1) "=" $2 }' \
        "$repo_root/source.lock"
    fi
    config_file="/boot/config-$(uname -r)"
    if [[ -r /proc/config.gz ]] && command -v zcat >/dev/null 2>&1; then
      zcat /proc/config.gz > "$out/.config.capture"
      config_file="$out/.config.capture"
    fi
    if [[ -r "$config_file" ]]; then
      config_hash=$(sha256sum "$config_file" | cut -d' ' -f1)
      printf 'config_sha256=%s\n' "$config_hash"
    else
      printf 'config_sha256=unavailable\n'
    fi
    printf 'power_profile=%s\n' "$(command -v powerprofilesctl >/dev/null 2>&1 && powerprofilesctl get 2>/dev/null || true)"
  } > "$out/metadata.txt"
  rm -f "$out/.config.capture"
  if command -v lspci >/dev/null 2>&1; then lspci -nnk > "$out/pci.txt" 2>&1 || true; fi
  lsmod > "$out/modules.txt" 2>&1 || true
  systemctl --failed --no-pager --plain > "$out/failed-services.txt" 2>&1 || true
  if command -v sensors >/dev/null 2>&1; then sensors > "$out/sensors.txt" 2>&1 || true; fi
  if [[ -r /sys/kernel/debug/vgaswitcheroo/switch ]]; then
    cat /sys/kernel/debug/vgaswitcheroo/switch > "$out/vgaswitcheroo.txt" 2>&1 || true
  fi
}

write_sample_header() {
  printf '%s\n' \
    'captured_at,sample,load1,context_switches,memory_psi_some_avg10,cpu_temp_max_mC,fan_rpm_max,battery_power_now_uW,ac_online,cpu0_idle_time_us' \
    > "$1"
}

append_sample() {
  local csv=$1 sample=$2 load1 ctxt psi temp fan power ac idle
  load1=$(awk '{ print $1 }' /proc/loadavg)
  ctxt=$(cpu_context_switches)
  psi=$(memory_psi_avg10 || true)
  temp=$(max_sysfs_glob '/sys/class/thermal/thermal_zone*/temp')
  fan=$(max_sysfs_glob '/sys/class/hwmon/hwmon*/fan*_input')
  power=$(sum_sysfs_glob '/sys/class/power_supply/BAT*/power_now')
  ac=$(read_first_line /sys/class/power_supply/ADP1/online || true)
  idle=$(sum_sysfs_glob '/sys/devices/system/cpu/cpu0/cpuidle/state*/time')
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date -Iseconds)" "$sample" "$load1" "$ctxt" "$psi" "$temp" "$fan" "$power" "$ac" "$idle" >> "$csv"
}
