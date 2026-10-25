#!/usr/bin/env bash
# Deterministic hardware-specific kernel configuration. Audit after olddefconfig.
set -euo pipefail
[[ $# -eq 1 && -f "$1/scripts/config" ]] || { echo "Usage: $0 /path/to/linux" >&2; exit 2; }
cd "$1"
config=./scripts/config
yes() { "$config" --enable "$1"; }
mod() { "$config" --module "$1"; }
no() { "$config" --disable "$1"; }

# Essential architecture, EFI, ACPI S3, SATA, userspace and runtime power control.
for s in EFI EFI_STUB PM ACPI SUSPEND CPU_IDLE CPU_FREQ \
  CPU_FREQ_GOV_SCHEDUTIL SMP MODULES MODVERSIONS PCI PCI_MSI \
  SCSI BLK_DEV_SD ATA SATA_AHCI EXT4_FS VFAT_FS \
  DEVTMPFS DEVTMPFS_MOUNT INPUT INPUT_EVDEV HID HID_GENERIC USB USB_HID \
  NET INET WIRELESS RFKILL SOUND SND HWMON THERMAL \
  FB VGA_SWITCHEROO PERF_EVENTS DEBUG_FS FTRACE \
  LRU_GEN LRU_GEN_ENABLED CRYPTO_LZ4 \
  NO_HZ_IDLE PREEMPT_DYNAMIC SECCOMP SECCOMP_FILTER NAMESPACES CGROUPS \
  MEDIA_SUPPORT MEDIA_CAMERA_SUPPORT MEDIA_USB_SUPPORT VIDEO_DEV; do yes "$s"; done

for s in X86_ACPI_CPUFREQ BTRFS_FS CFG80211 ZRAM \
  DRM_NOUVEAU APPLE_GMUX SENSORS_APPLESMC HID_APPLE \
  MOUSE_BCM5974 FORCEDETH USB_OHCI_HCD USB_EHCI_HCD USB_XHCI_HCD \
  USB_STORAGE USB_VIDEO_CLASS BT_HCIBTUSB \
  SND_HDA_INTEL FIREWIRE_OHCI EXFAT_FS \
  USB_OHCI_HCD_PCI USB_EHCI_PCI; do mod "$s"; done

yes DRM
yes BT
yes FIREWIRE
if grep -q '^config HZ_500$' kernel/Kconfig.hz; then
  yes HZ_500
  "$config" --set-val HZ 500
else
  yes HZ_1000
  "$config" --set-val HZ 1000
fi
yes HIGH_RES_TIMERS
yes CC_OPTIMIZE_FOR_PERFORMANCE
no NO_HZ_FULL
no HIBERNATION
no ZSWAP  # Prevent duplicate compressed-swap layers; zram-generator owns LZ4 swap.
"$config" --set-str LOCALVERSION "-mbp51-extreme"
no LOCALVERSION_AUTO

# User-directed security trade-off: optional speculative CPU mitigations excluded.
no CPU_MITIGATIONS

# Keep debugfs and perf/ftrace for PowerTOP and vga_switcheroo, remove heavy diagnostics.
yes DEBUG_INFO_NONE
for s in DEBUG_INFO DEBUG_INFO_BTF KASAN KCSAN UBSAN LOCKDEP \
  PROVE_LOCKING DEBUG_LOCK_ALLOC KGDB KDB FAULT_INJECTION GCOV_KERNEL \
  FUNCTION_TRACER FUNCTION_GRAPH_TRACER; do no "$s"; done

# Remove unrelated graphics, networking, virtualization and specialized buses.
for s in DRM_AMDGPU DRM_RADEON DRM_I915 DRM_XE DRM_AST \
  WLAN_VENDOR_INTEL WLAN_VENDOR_REALTEK WLAN_VENDOR_ATH \
  WLAN_VENDOR_MEDIATEK WLAN_VENDOR_MARVELL WLAN_VENDOR_RALINK \
  INFINIBAND THUNDERBOLT USB4 HYPERV XEN KVM KVM_INTEL KVM_AMD \
  B43 B43LEGACY BRCMSMAC BRCMFMAC; do no "$s"; done

echo "Requested MBP5,1 configuration applied; must run olddefconfig and audit."
