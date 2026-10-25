#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/source.lock"
config="$1"
[[ -s "$config" ]] || { echo "Missing resolved .config" >&2; exit 2; }
fail=0
has_symbol() {
  grep -Eq "^CONFIG_$1=|^# CONFIG_$1 is not set$" "$config"
}
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
for s in CPU_MITIGATIONS HIBERNATION ZSWAP KASAN KCSAN UBSAN KVM \
  CGROUP_DEBUG; do expect "$s" n; done
if has_symbol DEBUG_INFO; then
  expect DEBUG_INFO n
else
  expect DEBUG_INFO_NONE y
fi
for s in MODULES MODVERSIONS EFI EFI_STUB ACPI SUSPEND SATA_AHCI BLK_DEV_SD EXT4_FS \
  CPU_IDLE CPU_FREQ CPU_FREQ_GOV_SCHEDUTIL CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
  NO_HZ_IDLE HIGH_RES_TIMERS PREEMPT_DYNAMIC PREEMPT_LAZY SCHED_AUTOGROUP \
  DEBUG_FS PERF_EVENTS FTRACE SMP FB VGA_SWITCHEROO DRM \
  LRU_GEN LRU_GEN_ENABLED CRYPTO_LZ4 ZRAM_BACKEND_LZ4 ZRAM_DEF_COMP_LZ4 \
  MEDIA_SUPPORT MEDIA_CAMERA_SUPPORT MEDIA_USB_SUPPORT VIDEO_DEV \
  SECCOMP SECCOMP_FILTER NAMESPACES USER_NS CGROUPS MEMCG PSI \
  ACPI_EC ACPI_BATTERY BTRFS_FS_POSIX_ACL \
  HWMON THERMAL; do expect "$s" y; done
if has_symbol HZ_500; then
  expect HZ_500 y
  expect HZ 500
else
  expect HZ_1000 y
  expect HZ 1000
fi
for s in DRM_NOUVEAU FORCEDETH SENSORS_APPLESMC HID_APPLE MOUSE_BCM5974 \
  USB_EHCI_HCD USB_OHCI_HCD SND_HDA_INTEL USB_VIDEO_CLASS CFG80211 \
  ZRAM BTRFS_FS X86_ACPI_CPUFREQ SND_HDA_CODEC_REALTEK \
  SND_USB_AUDIO ACPI_SBS SND_HDA_GENERIC; do expect "$s" m; done
for s in APPLE_GMUX USB_HID; do expect "$s" any; done
# Kconfig does not emit an explicitly disabled entry for the invisible
# FORCE_LZO derived symbol. LZ4=y + LZO disabled are the authoritative checks.
expect ZRAM_BACKEND_LZO n
expect ZRAM_DEF_COMP '"lz4"'
expect NR_CPUS 2
expect LOCALVERSION "\"$KERNEL_LOCALVERSION\""
[[ "$fail" == 0 ]] || { echo "Kconfig audit FAILED" >&2; exit 1; }
echo "Kconfig audit passed."
