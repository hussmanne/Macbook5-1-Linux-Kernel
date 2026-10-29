#!/usr/bin/env bash
# Deterministic hardware-specific kernel configuration for MacBookPro5,1.
# Audit after olddefconfig. See docs/KCONFIG-PROFILE.md for the rationale of
# every entry, including what is deliberately KEPT.
set -euo pipefail
[[ $# -eq 1 && -f "$1/scripts/config" ]] || { echo "Usage: $0 /path/to/linux" >&2; exit 2; }
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/scripts/tier-profile.sh"
cd "$1"
config=./scripts/config
yes() { "$config" --enable "$1"; }
mod() { "$config" --module "$1"; }
no() { "$config" --disable "$1"; }
set_hz() {
  local symbol="$1" value="$2" hz
  for hz in HZ_100 HZ_250 HZ_300 HZ_500 HZ_1000; do
    if grep -Eq "^[[:space:]]*config $hz$" kernel/Kconfig.hz; then
      no "$hz"
    fi
  done
  yes "$symbol"
  "$config" --set-val HZ "$value"
}

# ---------------------------------------------------------------------------
# 1. Essential architecture: EFI boot, ACPI S3, SATA, userspace, sandboxing.
#    These are non-negotiable; audit-config.sh fails the build without them.
# ---------------------------------------------------------------------------
for s in EFI EFI_STUB PM ACPI SUSPEND CPU_IDLE CPU_FREQ \
  CPU_FREQ_GOV_SCHEDUTIL SMP MODULES MODVERSIONS PCI PCI_MSI \
  SCSI BLK_DEV_SD ATA SATA_AHCI EXT4_FS VFAT_FS \
  DEVTMPFS DEVTMPFS_MOUNT INPUT INPUT_EVDEV HID HID_GENERIC USB USB_HID \
  NET INET WIRELESS RFKILL SOUND SND HWMON THERMAL \
  VGA_SWITCHEROO PERF_EVENTS DEBUG_FS FTRACE DRM \
  LRU_GEN LRU_GEN_ENABLED CRYPTO_LZ4 \
  NO_HZ_IDLE PREEMPT_DYNAMIC SECCOMP SECCOMP_FILTER NAMESPACES USER_NS \
  CGROUPS MEMCG PSI ACPI_EC ACPI_BATTERY I2C BTRFS_FS_POSIX_ACL \
  MEDIA_SUPPORT MEDIA_CAMERA_SUPPORT MEDIA_USB_SUPPORT VIDEO_DEV \
  BT FIREWIRE IKCONFIG IKCONFIG_PROC; do yes "$s"; done

# ---------------------------------------------------------------------------
# 2. Console. This machine has no serial port and no text-mode fallback: the
#    EFI firmware starts the panel in graphics mode, so a kernel WITHOUT
#    fbcon is silent until Xorg grabs DRM. Nouveau on this development tree
#    already emits DRM warnings, so the console is the only way to see a
#    failed mode set or a failed mount. Costs a few hundred KiB.
# ---------------------------------------------------------------------------
yes FB
yes FRAMEBUFFER_CONSOLE
yes DRM_FBDEV_EMULATION
yes FB_EFI

# ---------------------------------------------------------------------------
# 3. Real hardware on this exact machine, as modules so the initramfs stays
#    small and a driver failure cannot prevent boot. Anything not present on
#    a MacBookPro5,1 does not go here.
# ---------------------------------------------------------------------------
for s in X86_ACPI_CPUFREQ BTRFS_FS CFG80211 ZRAM \
  DRM_NOUVEAU APPLE_GMUX SENSORS_APPLESMC HID_APPLE HID_APPLEIR \
  MOUSE_BCM5974 FORCEDETH USB_OHCI_HCD USB_EHCI_HCD USB_XHCI_HCD \
  USB_STORAGE USB_VIDEO_CLASS BT_HCIBTUSB \
  SND_HDA_INTEL SND_HDA_CODEC_REALTEK SND_USB_AUDIO ACPI_SBS \
  FIREWIRE_OHCI EXFAT_FS \
  USB_OHCI_HCD_PCI USB_EHCI_PCI SENSORS_CORETEMP; do mod "$s"; done

# ---------------------------------------------------------------------------
# 3b. Capabilities the *installed OS* needs, which x86_64_defconfig omits.
#     Removing hardware that cannot exist here is only worth doing because it
#     pays for these: without them the machine boots but is not a usable
#     EndeavourOS desktop.
# ---------------------------------------------------------------------------
# FUSE: AppImage, Flatpak, sshfs, fuse-based backup tools.
mod FUSE_FS
# OverlayFS: Flatpak runtimes, podman/docker overlay2, systemd-sysext.
mod OVERLAY_FS
# nftables. Arch ships iptables-nft and firewalld talks to nf_tables, so
# without this the laptop has no working packet filter at all (legacy
# ip_tables alone is not what any EndeavourOS firewall front-end uses).
mod NF_TABLES
# NF_TABLES_INET and NF_TABLES_IPV4/IPV6 are BOOLS (selected, not tristate).
# `--module` on a bool resolves to n, which silently disables the whole
# inet/NAT table family; they must be enabled with `yes`.
yes NF_TABLES_INET   # also selects NF_TABLES_IPV4 and NF_TABLES_IPV6
mod NFT_COMPAT   # x_tables extensions over nf_tables: iptables-nft, firewalld
mod NFT_NAT      # depends on NF_TABLES_IPV4/IPV6, hence the `yes` above
mod NFT_CT
mod NF_NAT
# AppArmor: ENGINEERING.md requires non-mitigation security features to be
# preserved. Arch's userspace ships apparmor; the stock kernel provides it.
yes SECURITY_APPARMOR
# bpf(): needed by systemd cgroup features and by bpftrace/perf-based
# profiling, which is the tooling this project uses to measure tiers.
# Unprivileged BPF stays disabled by default (BPF_UNPRIV_DEFAULT_OFF).
yes BPF_SYSCALL
yes CGROUP_BPF
# dm-crypt is one module of insurance: the current root is unencrypted, but a
# missing dm_crypt turns any later LUKS decision into an unbootable machine.
mod DM_CRYPT
# Network filesystems as modules rather than built in.
mod NFS_FS

# The MCP79 HDA controller requires an actual codec driver for internal audio.
mod SND_HDA_GENERIC
# Remove unneeded cgroup debugging. AMD P-state is selected by upstream
# processor Kconfig even on Intel builds; it cannot be disabled here.
no CGROUP_DEBUG

# ---------------------------------------------------------------------------
# 4. Scheduler / tick selection. Exactly one variable per tier.
# ---------------------------------------------------------------------------
if [[ "$MBP51_TIER" == bore ]]; then
  yes SCHED_BORE
  "$config" --set-val MIN_BASE_SLICE_NS 2000000
  set_hz HZ_1000 1000
elif [[ "$MBP51_TIER" == lab ]]; then
  # Lab isolates the tick-rate variable and preserves every recovered feature
  # (audio, UPower/userspaces, ACLs, battery/SMC, both GPUs, Wi-Fi, input,
  # thermal). It is a latency-granularity experiment, not a power experiment:
  # NO_HZ_IDLE already stops the tick when idle.
  set_hz HZ_250 250
elif grep -Eq '^[[:space:]]*config HZ_500$' kernel/Kconfig.hz; then
  set_hz HZ_500 500
else
  set_hz HZ_1000 1000
fi
# NOTE: `no SCHED_SMT` is deliberately NOT set here. The P8600 has no SMT
# siblings so the domain can never be populated, but the symbol is a visible
# `default y` bool and its resolution has not been proven by a real
# `make olddefconfig` run in CI. Add it only together with a passing
# audit line, per docs/KCONFIG-PROFILE.md.
# Fixed Penryn Core 2 Duo machine: only two execution cores; retain SMP.
"$config" --set-val NR_CPUS 2
# Use scheduler-coupled ACPI frequency scaling and desktop process grouping.
yes CPU_FREQ_DEFAULT_GOV_SCHEDUTIL
yes SCHED_AUTOGROUP
# Build TEO alongside the default menu governor so the idle-governor comparison
# is a runtime experiment (echo teo > /sys/devices/system/cpu/cpuidle/...)
# rather than a rebuild. Default behaviour is unchanged.
yes CPU_IDLE_GOV_TEO

# ---------------------------------------------------------------------------
# 5. Memory: LZ4 zram only. The backend is separate from CRYPTO_LZ4; without
#    it zram-generator's compression-algorithm=lz4 is rejected at runtime.
# ---------------------------------------------------------------------------
yes ZRAM_BACKEND_LZ4
yes ZRAM_DEF_COMP_LZ4
no ZRAM_BACKEND_LZO
yes HIGH_RES_TIMERS
yes CC_OPTIMIZE_FOR_PERFORMANCE
no NO_HZ_FULL
no HIBERNATION
no ZSWAP  # Prevent duplicate compressed-swap layers; zram-generator owns LZ4 swap.
"$config" --set-str LOCALVERSION "$KERNEL_LOCALVERSION"
no LOCALVERSION_AUTO

# User-directed security trade-off: optional speculative CPU mitigations excluded.
no CPU_MITIGATIONS

# ---------------------------------------------------------------------------
# 6. Debug/tracing policy. KEEP debugfs, perf and ftrace (PowerTOP, scheduling
#    work); KEEP PM_DEBUG (/sys/power/pm_test is how suspend gets triaged
#    without risking an unrecoverable hang) and BLK_DEV_IO_TRACE (blktrace for
#    the SATA ALPM integrity work). Remove only what costs runtime overhead or
#    is pure crash-debugger machinery.
# ---------------------------------------------------------------------------
yes DEBUG_INFO_NONE
for s in DEBUG_INFO DEBUG_INFO_BTF KASAN KCSAN UBSAN LOCKDEP \
  PROVE_LOCKING DEBUG_LOCK_ALLOC KGDB KDB FAULT_INJECTION GCOV_KERNEL \
  FUNCTION_TRACER FUNCTION_GRAPH_TRACER \
  SCHEDSTATS PM_TRACE_RTC KALLSYMS_ALL DEBUG_STACK_USAGE DEBUG_ENTRY \
  DEBUG_BOOT_PARAMS EARLY_PRINTK_DBGP PROVIDE_OHCI1394_DMA_INIT \
  X86_CHECK_BIOS_CORRUPTION; do no "$s"; done

# ---------------------------------------------------------------------------
# 7. Remove hardware and subsystems that cannot exist on a MacBookPro5,1.
#    Unlike the previous list, every symbol here is actually enabled by
#    x86_64_defconfig, so each line changes the built kernel.
# ---------------------------------------------------------------------------
# Virtualisation guest stack: this kernel runs on bare metal, never as a guest.
for s in VIRTIO VIRTIO_PCI VIRTIO_BLK VIRTIO_NET VIRTIO_INPUT \
  VIRTIO_CONSOLE SCSI_VIRTIO NET_9P NET_9P_VIRTIO 9P_FS \
  HYPERV XEN KVM KVM_INTEL KVM_AMD; do no "$s"; done
# Wired NICs: the machine has exactly one Ethernet port (forcedeth).
for s in E100 E1000 E1000E R8169 TIGON3 NET_TULIP SKY2 8139TOO; do no "$s"; done
# Network-root boot path (IP_PNP/ROOT_NFS): no diskless boot here.
for s in IP_PNP IP_PNP_DHCP IP_PNP_BOOTP IP_PNP_RARP ROOT_NFS; do no "$s"; done
# The 15-inch unibody has an ExpressCard/34 slot, not PCMCIA/CardBus.
for s in PCCARD YENTA; do no "$s"; done
# Single-socket, single-node, two-core machine.
no NUMA
# Unused LSM and graphics families.
for s in SECURITY_SELINUX AGP AGP_INTEL AGP_AMD64 DRM_I915 DRM_VIRTIO_GPU DRM_AMDGPU DRM_RADEON DRM_XE DRM_AST; do no "$s"; done
# No driver exists behind these wireless menus; keeping the menus off removes
# nothing by itself but documents the wl-first policy unambiguously.
for s in WLAN_VENDOR_INTEL WLAN_VENDOR_REALTEK WLAN_VENDOR_ATH \
  WLAN_VENDOR_MEDIATEK WLAN_VENDOR_MARVELL WLAN_VENDOR_RALINK \
  B43 B43LEGACY BRCMSMAC BRCMFMAC; do no "$s"; done
# Thunderbolt/USB4/InfiniBand cannot be present on MCP79.
for s in INFINIBAND THUNDERBOLT USB4; do no "$s"; done
# Software suspend already replaces hibernation on this machine.
no NO_HZ_FULL

echo "Requested MBP5,1 configuration applied; must run olddefconfig and audit."
