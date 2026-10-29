#!/usr/bin/env bash
# Read-only, bounded MacBookPro5,1 comparison for stock LTS and custom kernels.
# Run once while booted into each kernel; does not alter boot, GPUs, or power.
set -uo pipefail
[[ "${EUID}" -ne 0 ]] || { echo "Run as regular user (not root)" >&2; exit 2; }
mkdir -p "$HOME/mbp51-audit"
output="$HOME/mbp51-audit/compare-$(uname -r).txt"
echo "This comparison does not modify hardware or services."
if command -v sudo >/dev/null; then sudo -v || echo "Kernel log/switcheroo may be omitted."; fi
report() {
  echo "=== TIME / KERNEL ==="
  date -Iseconds; uname -a; cat /proc/cmdline
  echo "=== ACPI POWER SUPPLIES ==="
  ls -l /sys/class/power_supply/ 2>&1 || :
  for d in /sys/class/power_supply/*; do
    [[ -d "$d" ]] || continue
    echo "device=$d"
    for k in type status capacity online present energy_full energy_full_design energy_now power_now voltage_now; do
      [[ -r "$d/$k" ]] && printf '%s=%s\n' "$k" "$(cat "$d/$k")"
    done
  done
  echo "=== ACPI BATTERY FIRMWARE ==="
  for d in /sys/bus/acpi/devices/PNP0C0A:*; do
    [[ -d "$d" ]] && { echo "$d"; cat "$d/status" 2>&1 || :; }
  done
  echo "=== UPOWER ==="
  timeout -k 2 5 upower -e 2>&1 || :
  systemctl --no-pager --plain is-active upower.service 2>&1 || :
  echo "=== AUDIO ==="
  cat /proc/asound/cards 2>&1 || :
  timeout -k 2 5 aplay -l 2>&1 || :
  echo "=== BLUETOOTH ==="
  timeout -k 2 5 bluetoothctl list 2>&1 || echo "Bluetooth query failed or timed out"
  echo "=== GPU / DISPLAY ==="
  lspci -nnk | grep -A4 -E 'VGA compatible controller|Audio device' || :
  timeout -k 2 8 xrandr --listproviders 2>&1 || :
  for d in /sys/class/backlight/*; do
    [[ -d "$d" ]] || continue
    echo "backlight=$d"
    for k in brightness actual_brightness max_brightness bl_power; do
      [[ -r "$d/$k" ]] && printf '%s=%s\n' "$k" "$(cat "$d/$k")"
    done
  done
  if sudo -n true 2>/dev/null; then
    timeout -k 2 5 sudo -n cat /sys/kernel/debug/vgaswitcheroo/switch 2>&1 || :
  fi
  echo "=== THERMAL ==="
  timeout -k 2 10 sensors 2>&1 || :
  echo "=== MEMORY AND IDLE STATES ==="
  swapon --show 2>&1 || :
  for d in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
    [[ -r "$d/name" ]] && printf '%s %s %s\n' "$(cat "$d/name")" "$(cat "$d/usage")" "$(cat "$d/time")"
  done
  echo "=== SERVICE ERRORS ==="
  systemctl --failed --no-pager 2>&1 || :
  echo "=== KERNEL WARNINGS ==="
  if sudo -n true 2>/dev/null; then
    timeout -k 2 15 sudo -n journalctl -k -b --no-pager -p warning..emerg -n 60 2>&1 || :
  else
    echo 'No cached sudo authentication; kernel log omitted.'
  fi
  echo "=== COMPARISON COMPLETE ==="
}
report 2>&1 | tee "$output"
echo "Saved to $output"
