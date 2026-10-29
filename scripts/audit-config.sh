#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/scripts/tier-profile.sh"
config="$1"
[[ -s "$config" ]] || { echo "Missing resolved .config" >&2; exit 2; }
fail=0
has_symbol() {
  grep -Eq "^CONFIG_$1=|^# CONFIG_$1 is not set$" "$config"
}
# Absent symbols are legitimate: Kconfig omits a tristate entirely when its
# dependency menu is closed (e.g. 9P_FS after NET_9P=n). Both "no" and "gone
# with its dependency" mean the code is not built.
expect_gone() {
  local symbol="$1" actual
  if grep -Fxq "# CONFIG_$symbol is not set" "$config"; then
    return 0
  fi
  if ! has_symbol "$symbol"; then
    return 0
  fi
  actual=$(sed -n "s/^CONFIG_$symbol=//p" "$config" | tail -n 1)
  echo "ERROR: CONFIG_$symbol must be disabled; resolved [$actual]" >&2
  fail=1
  return 0
}
expect() {
  local symbol="$1" wanted="$2" actual
  actual=$(sed -n "s/^CONFIG_$symbol=//p" "$config" | tail -n 1)
  if [[ "$wanted" == n ]]; then
    if grep -Fxq "# CONFIG_$symbol is not set" "$config"; then return 0; fi
  elif [[ "$wanted" == any ]]; then
    if [[ "$actual" == y || "$actual" == m ]]; then return 0; fi
  elif [[ "$actual" == "$wanted" ]]; then
    return 0
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
  FB FRAMEBUFFER_CONSOLE DRM_FBDEV_EMULATION FB_EFI IKCONFIG IKCONFIG_PROC \
  CPU_IDLE_GOV_TEO HWMON THERMAL \
  NF_TABLES_INET NF_TABLES_IPV4 NF_TABLES_IPV6 \
  SECURITY_APPARMOR BPF_SYSCALL CGROUP_BPF; do expect "$s" y; done
if has_symbol HZ_500; then
  if [[ "$MBP51_TIER" == bore ]]; then
    expect HZ_1000 y
    expect HZ 1000
  elif [[ "$MBP51_TIER" == lab ]]; then
    expect HZ_250 y
    expect HZ 250
  else
    expect HZ_500 y
    expect HZ 500
  fi
elif [[ "$MBP51_TIER" == lab ]]; then
  expect HZ_250 y
  expect HZ 250
else
  expect HZ_1000 y
  expect HZ 1000
fi
if [[ "$MBP51_TIER" == bore ]]; then
  expect SCHED_BORE y
  expect MIN_BASE_SLICE_NS 2000000
fi
for s in DRM_NOUVEAU FORCEDETH SENSORS_APPLESMC HID_APPLE MOUSE_BCM5974 \
  USB_EHCI_HCD USB_OHCI_HCD SND_HDA_INTEL USB_VIDEO_CLASS CFG80211 \
  ZRAM BTRFS_FS X86_ACPI_CPUFREQ SND_HDA_CODEC_REALTEK \
  SND_USB_AUDIO ACPI_SBS SND_HDA_GENERIC SENSORS_CORETEMP HID_APPLEIR \
  FUSE_FS OVERLAY_FS NF_TABLES NFT_COMPAT NFT_NAT NFT_CT NF_NAT \
  DM_CRYPT NFS_FS; do
  expect "$s" m
done
for s in APPLE_GMUX USB_HID; do expect "$s" any; done
# Kconfig does not emit an explicitly disabled entry for the invisible
# FORCE_LZO derived symbol. LZ4=y + LZO disabled are the authoritative checks.
expect ZRAM_BACKEND_LZO n
expect ZRAM_DEF_COMP '"lz4"'
# Nothing that cannot exist on this machine may be built in. These were all
# enabled by x86_64_defconfig and are the reason c2 is a real trim.
for s in VIRTIO VIRTIO_PCI VIRTIO_CONSOLE NET_9P 9P_FS SCSI_VIRTIO \
  E100 E1000 E1000E R8169 TIGON3 NET_TULIP SKY2 8139TOO IP_PNP ROOT_NFS \
  PCCARD YENTA NUMA SECURITY_SELINUX AGP AGP_INTEL DRM_I915 DRM_VIRTIO_GPU \
  SCHEDSTATS KALLSYMS_ALL; do expect_gone "$s"; done
expect NR_CPUS 2
expect LOCALVERSION "\"$KERNEL_LOCALVERSION\""
[[ "$fail" == 0 ]] || { echo "Kconfig audit FAILED" >&2; exit 1; }
echo "Kconfig audit passed."
