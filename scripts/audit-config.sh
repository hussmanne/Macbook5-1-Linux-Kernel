#!/usr/bin/env bash
set -euo pipefail
config="$1"
[[ -s "$config" ]] || { echo "Missing resolved .config" >&2; exit 2; }
fail=0
expect() {
  local symbol="$1" wanted="$2" actual
  actual=$(sed -n "s/^CONFIG_$symbol=//p" "$config" | tail -n 1)
  if [[ "$wanted" == n ]]; then
    grep -Fxq "# CONFIG_$symbol is not set" "$config" && return
  elif [[ "$wanted" == any ]]; then
    [[ "$actual" == y || "$actual" == m ]] && return
  elif [[ "$actual" == "$wanted" ]]; then return
  fi
  echo "ERROR: CONFIG_$symbol must be $wanted; resolved [$actual]" >&2
  fail=1
}
for s in CPU_MITIGATIONS HIBERNATION DEBUG_INFO KASAN KCSAN UBSAN KVM; do expect "$s" n; done
for s in MODULES MODVERSIONS EFI ACPI SUSPEND SATA_AHCI BLK_DEV_SD EXT4_FS \
  CPU_IDLE CPU_FREQ NO_HZ_IDLE DEBUG_FS PERF_EVENTS HZ_500; do expect "$s" y; done
for s in DRM_NOUVEAU FORCEDETH SENSORS_APPLESMC HID_APPLE MOUSE_BCM5974 \
  USB_EHCI_HCD USB_OHCI_HCD SND_HDA_INTEL USB_VIDEO_CLASS CFG80211 \
  ZRAM BTRFS_FS; do expect "$s" m; done
for s in APPLE_GMUX VGA_SWITCHEROO USB_HID; do expect "$s" any; done
[[ "$fail" == 0 ]] || { echo "Kconfig audit FAILED" >&2; exit 1; }
echo "Kconfig audit passed."
