#!/usr/bin/env bash
# Read-only MacBook5,1 qualification evidence. Does not suspend, reboot,
# tune power, install software, or change live kernel state.
set -uo pipefail
if [[ "$EUID" -eq 0 ]]; then
  echo "Run without sudo to avoid changing system state." >&2
  exit 2
fi
section() { printf '\n===== %s =====\n' "$1"; }
try() {
  label=$1
  shift
  section "$label"
  if command -v "$1" >/dev/null 2>&1; then "$@" 2>&1 || :; else echo "Not installed: $1"; fi
}
section "Machine and kernel"
date -Iseconds
uname -a
cat /proc/cmdline
try "GPU, chipset, and Wi-Fi PCI IDs" lspci -nnk
try "Module versions and conflicts" lsmod
try "Wireless module version and source" modinfo wl
try "Current network adapter state" nmcli -f DEVICE,TYPE,STATE device
try "CPU frequency policies" cpupower frequency-info
try "Storage and mounted boot volumes" findmnt -o SOURCE,TARGET,FSTYPE
try "Existing kernel packages" pacman -Q linux linux-headers linux-lts linux-lts-headers linux-mbp51-extreme linux-mbp51-extreme-headers mbp51-broadcom-wl
try "DKMS state" dkms status
try "Memory/swap/zram" swapon --show
try "CPU and idle stats" cat /proc/stat
try "SMC and thermal sensors" sensors
section "Battery power_supply attributes"
for battery in /sys/class/power_supply/BAT*; do
  [[ -d "$battery" ]] || continue
  for key in status capacity energy_now energy_full power_now voltage_now current_now; do
    [[ -r "$battery/$key" ]] && printf '%s=%s\n' "$key" "$(cat "$battery/$key")"
  done
done
section "Nouveau errors and suspend/kernel diagnostics"
if command -v journalctl >/dev/null; then
  journalctl -k -b --no-pager -p warning..emerg -n 150 2>&1 || :
fi
section "Manual next steps (not executed)"
echo "Verify screen, both GPUs, trackpad, webcam, Ethernet, audio, and Wi-Fi."
echo "Capture baseline idle watts and temperatures before global powertop --auto-tune."
echo "Test suspend and lid-close only after confirming stock-kernel recovery."
echo "Run this script again after manually resuming, and compare diagnostics."
