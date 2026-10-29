# MacBookPro5,1 kernel configuration profile (`c2`)

This is the answer to "what is in the kernel, what is out, and why" for **this
laptop**. It describes the single shared hardware profile that all three tiers
are built from.

Related: [three-tier architecture](THREE-TIER-MULTIBOOT.md),
[engineering contract](ENGINEERING.md), [2026-10-29 review](REVIEW-2026-10-29.md).

---

## 1. Three builds, one hardware profile

The repository produces three separately packaged, separately bootable
kernels. They are **not** three different hardware configurations — that would
be a bug, not a feature: if each tier trimmed hardware differently, a failure
in one tier would tell you nothing about the others.

What is shared: upstream source pin, this configuration, packaging, installer,
Dracut flow, Broadcom tooling.

What differs, per tier, is exactly one experiment:

| Tier | Package | Configuration difference from Daily |
|---|---|---|
| Daily | `linux-mbp51-daily` | *(reference)* |
| BORE | `linux-mbp51-bore` | `CONFIG_SCHED_BORE=y`, `CONFIG_MIN_BASE_SLICE_NS=2000000` |
| Lab | `linux-mbp51-extreme-lab` | `CONFIG_HZ_250=y`, `CONFIG_HZ=250` |
| legacy v2 | `linux-mbp51-extreme` | none — identical configuration to Daily |

Legacy v2 is a duplicate build kept for compatibility with the one kernel that
has actually booted on the machine. It is not a fourth experiment.

**Consequence to keep in mind:** because all tiers share one source and one
config, they share failure modes. `linux-lts` is the only genuinely independent
kernel on the machine.

---

## 2. What is deliberately IN

Everything here is required for the machine to be a working laptop, or is a
diagnostic path the project depends on.

### Boot and storage
`EFI`, `EFI_STUB`, `EFIVAR_FS`, `SATA_AHCI`, `BLK_DEV_SD`, `SCSI`,
`BTRFS_FS`, `BTRFS_FS_POSIX_ACL`, `EXT4_FS`, `VFAT_FS`, `ISO9660_FS` (boot
media), `TMPFS`, `DEVTMPFS_MOUNT`, `BLK_DEV_DM` (+ `DM_CRYPT`), `MD`.

`DM_CRYPT` is one module of insurance. The planned root is unencrypted, but a
kernel without it turns any later LUKS decision into an unbootable machine.

### Console and fallbacks
`FB`, `FRAMEBUFFER_CONSOLE`, `DRM_FBDEV_EMULATION`, `FB_EFI`.

There is **no serial port** and no text-mode VGA path on a panel the firmware
has already switched into graphics mode. Without fbcon a failed modeset, a
failed mount or a panicking initramfs produces a black screen and nothing else.
This is the single most important debug capability on this machine.

### Power, thermal, ACPI
`ACPI`, `ACPI_EC`, `ACPI_BATTERY`, `ACPI_SBS` (diagnostic), `ACPI_FAN`,
`ACPI_THERMAL`, `SUSPEND` (S3), `CPU_IDLE`, `CPU_FREQ`, `X86_ACPI_CPUFREQ`,
`CPU_FREQ_DEFAULT_GOV_SCHEDUTIL`, `CPU_IDLE_GOV_MENU` + `CPU_IDLE_GOV_TEO`,
`SENSORS_APPLESMC`, `SENSORS_CORETEMP`, `HWMON`, `THERMAL`.

`HIBERNATION` is off: the plan is suspend-to-RAM, and `linux-lts` keeps
hibernation available. The SSD is not used as a hibernate target.

Building **both** idle governors makes the menu-vs-TEO comparison a runtime
experiment (`/sys/devices/system/cpu/cpuidle/current_governor`) instead of a
rebuild. The default is unchanged.

### Graphics
`DRM`, `DRM_NOUVEAU`, `DRM_NOUVEAU_BACKLIGHT`, `DRM_TTM`, `APPLE_GMUX`,
`BACKLIGHT_CLASS_DEVICE`, `VGA_SWITCHEROO`, `FB`.

Both GPUs stay supported. Nothing automatically powers a rail off.

### Networking
`NET`, `INET`, `CFG80211`, `WIRELESS`, `RFKILL` (out-of-tree `wl` for the
BCM4322), `FORCEDETH` (the one wired port), `BT` + `BT_HCIBTUSB`,
`NF_TABLES` + `NF_TABLES_INET` + `NFT_COMPAT` + `NFT_NAT` + `NFT_CT` +
`NF_NAT`, `NETFILTER_XTABLES`, `IP_NF_IPTABLES`, `NETCONSOLE` (log over UDP
when the screen is dead).

`NF_TABLES` deserves emphasis: Arch ships `iptables-nft` and firewalld speaks
nf_tables. A kernel without it boots fine and then has **no working packet
filter**, which is not acceptable on a laptop joined to other people's Wi-Fi.
`x86_64_defconfig` does not enable it.

### Input, audio, peripherals
`HID`, `USB_HID`, `HID_GENERIC`, `HID_APPLE`, `HID_APPLEIR`, `MOUSE_BCM5974`,
`INPUT_EVDEV`, `SOUND`, `SND`, `SND_HDA_INTEL`, `SND_HDA_CODEC_REALTEK`,
`SND_HDA_GENERIC`, `SND_HDA_HWDEP`, `SND_USB_AUDIO`, `USB` (OHCI/EHCI/XHCI),
`USB_STORAGE`, `USB_VIDEO_CLASS` (+ media stack), `FIREWIRE_OHCI`.

`HID_APPLEIR` and `SENSORS_CORETEMP` were missing before `c2` despite the
repository rule "keep all real hardware": the IR receiver and the per-core
Penryn thermal sensors both exist on this machine.

### Userspace and sandboxing
`USER_NS`, `NAMESPACES`, `MEMCG`, `PSI`, `CGROUPS`, `SECCOMP`,
`SECCOMP_FILTER`, `SECURITY`, `SECURITY_NETWORK`, `SECURITY_APPARMOR`,
`AUDIT`, `FUSE_FS`, `OVERLAY_FS`, `BPF_SYSCALL`, `CGROUP_BPF`.

These were the real v1 regressions: without `USER_NS`/`MEMCG`/`PSI`, UPower and
systemd user sessions failed.

`FUSE_FS` and `OVERLAY_FS` are not optional on an EndeavourOS desktop —
AppImages, Flatpak, podman/docker and `systemd-sysext` all need them, and
`x86_64_defconfig` enables neither.

`BPF_SYSCALL`/`CGROUP_BPF` are kept because systemd uses cgroup BPF and because
`bpftrace`/`perf` are the profiling tools this project needs to compare tiers.
Unprivileged BPF remains disabled by default.

`SECURITY_APPARMOR` follows the documented rule that security features other
than the explicitly opted-out speculative-execution mitigations must be
preserved.

### Memory
`LRU_GEN` + `LRU_GEN_ENABLED` (MGLRU), `ZRAM` with `ZRAM_BACKEND_LZ4` and
`ZRAM_DEF_COMP="lz4"`, `ZSWAP` **off** (one compressed-swap layer only),
`SWAP` with disk fallback, `HIGH_RES_TIMERS`, `NO_HZ_IDLE`.

### Tracing, kept on purpose
`DEBUG_FS`, `PERF_EVENTS`, `FTRACE`, `PM_DEBUG`, `BLK_DEV_IO_TRACE`.

`PM_DEBUG` provides `/sys/power/pm_test`, which is how suspend gets triaged
without risking an unrecoverable hang on an untested machine.
`BLK_DEV_IO_TRACE` provides `blktrace`, which the SATA ALPM integrity work
needs. `KALLSYMS` (but not `KALLSYMS_ALL`) is kept for oops decoding.

### Deliberately retained despite looking obsolete
`KEXEC` — `systemctl kexec` is the fast way to switch between four boot entries
during tier testing. `IA32_EMULATION` — 32-bit userspace (Wine, some Steam
titles, old binaries). `SERIAL_8250*` — no port exists, but it costs almost
nothing and someone may attach a USB-serial adapter for early-boot debugging.

---

## 3. What is deliberately OUT

Every symbol in this section was **enabled by `x86_64_defconfig`** and is now
built as `n`, so each line changes the produced kernel.

### Cannot exist on this machine
| Symbol(s) | Reason |
|---|---|
| `VIRTIO`, `VIRTIO_PCI`, `VIRTIO_BLK`, `VIRTIO_NET`, `VIRTIO_INPUT`, `VIRTIO_CONSOLE`, `SCSI_VIRTIO`, `NET_9P`, `NET_9P_VIRTIO`, `9P_FS` | the kernel is never a virtualisation guest; no 9p mount plan |
| `HYPERV`, `XEN`, `KVM`, `KVM_INTEL`, `KVM_AMD` | no hypervisor role |
| `DRM_I915`, `DRM_VIRTIO_GPU`, `DRM_AMDGPU`, `DRM_RADEON`, `DRM_XE`, `DRM_AST` | no such display hardware |
| `E100`, `E1000`, `E1000E`, `R8169`, `TIGON3`, `NET_TULIP`, `SKY2`, `8139TOO` | the only wired NIC is MCP79 `forcedeth` |
| `PCCARD`, `YENTA` | the 15-inch unibody has ExpressCard/34, not CardBus |
| `AGP`, `AGP_INTEL`, `AGP_AMD64` | PCIe only |
| `NUMA` | one socket, one node, two cores |
| `INFINIBAND`, `THUNDERBOLT`, `USB4` | absent on MCP79 |
| `IP_PNP`, `IP_PNP_DHCP`, `IP_PNP_BOOTP`, `IP_PNP_RARP`, `ROOT_NFS` | no network-root boot |

### Policy exclusions
| Symbol(s) | Reason |
|---|---|
| `B43`, `B43LEGACY`, `BRCMSMAC`, `BRCMFMAC`, WLAN vendor menus | wl-first policy; only the patched proprietary `wl` drives the BCM4322 |
| `SECURITY_SELINUX` | not used by Arch/EndeavourOS |
| `HIBERNATION` | suspend-to-RAM is the plan; LTS keeps hibernation |
| `ZSWAP` | would duplicate the zram LZ4 layer |
| `CPU_MITIGATIONS` | **user-directed** security reduction — irreversible on this binary |

### Overhead removed
`SCHEDSTATS`, `KALLSYMS_ALL`, `PM_TRACE_RTC`, `DEBUG_STACK_USAGE`,
`DEBUG_ENTRY`, `DEBUG_BOOT_PARAMS`, `EARLY_PRINTK_DBGP`,
`PROVIDE_OHCI1394_DMA_INIT`, `X86_CHECK_BIOS_CORRUPTION`, `CGROUP_DEBUG`.

`SCHEDSTATS` is the only one of these in a hot path this project cares about
(`enqueue`/`dequeue`/context-switch accounting).

---

## 4. Measured effect of `c2`

Resolved offline from the pinned source with `scripts/configure.sh` +
`scripts/audit-config.sh` for all four tiers (audit passes for each):

| Metric | `c1` | `c2` |
|---|---|---|
| Symbols `=y` | 1622 | 1572 |
| Symbols `=m` | 93 | 122 |
| Symbols turned **off** that were built | — | 90 |
| Symbols turned **on** that were not built | — | 70 |
| Total config-line deltas vs `c1` | — | 320 |

Interpretation: `c2` removes more code than it adds. The additions are mostly
small capability modules (FUSE, overlayfs, nf_tables, dm-crypt); the removals
include `i915`, the virtio stack, eight NIC drivers, NUMA and `KALLSYMS_ALL`.

**These are symbol counts, not byte counts.** No size or performance claim is
made here; the CI build publishes the real `vmlinuz` and installed-module sizes,
and only those numbers should be quoted.

---

## 5. What stripping does and does not buy

- Smaller kernel image, slightly faster boot, fewer drivers auto-probing.
- **No** measurable battery improvement. Idle power on this machine is dominated
  by the display, the chipset and the second GPU's idle draw, not by unused
  module code. `ENGINEERING.md` already says this; it remains true.
- The 11 MiB `vmlinuz` was never the problem. The 146 MiB generic Dracut image
  was — hence host-only primary plus generic fallback.

---

## 6. Changing this profile

1. Edit `scripts/configure.sh`.
2. Add or update the corresponding `expect` line in `scripts/audit-config.sh`,
   so CI fails loudly if the symbol stops resolving.
3. Bump `MBP51_CONFIG_REV` in `source.lock`. This changes every tier's
   `LOCALVERSION` and therefore every vermagic.

Step 3 is not optional. A different `.config` under an identical release string
silently mismatches a previously built external module: `HZ` and most struct
layouts are **not** encoded in vermagic, so a stale `wl.ko` would load and
corrupt memory rather than being rejected.

### Traps found while building `c2`

- **`--module` on a `bool` resolves to `n`.** `NF_TABLES_INET` and
  `NF_TABLES_IPV4/IPV6` are bools; using `mod` silently produced a kernel with
  no `inet` table family. Generated `CONFIG_X=m` for a bool is dropped.
- **`depends on X if Y` and bare `transitional`/`modules` lines** are not
  handled by kconfiglib 14.1, so offline verification needs a patched throwaway
  tree. Only the CI build is authoritative.
- **Absent is not the same as `n`.** Kconfig omits a tristate entirely when its
  dependency menu closes (`9P_FS` after `NET_9P=n`), so the audit uses
  `expect_gone` rather than a strict "is not set" match.
- **`SCHED_SMT`** would be a legitimate micro-optimisation (the P8600 has no SMT
  siblings) but its resolution could not be proven offline, so it is
  deliberately **not** set. Add it only together with a passing audit line.

---

## 7. Remaining candidates, not removed yet

Listed with the reason they were left alone; none of them is worth a risk:

| Symbol | Why it is still present |
|---|---|
| `ATA_PIIX`, `PATA_AMD`, `PATA_OLDPIIX`, `PATA_SCH` | MCP79 is AHCI, but keeping them costs little and protects against an odd boot path or an external optical drive |
| `SERIAL_8250*` | no port, but a USB-serial adapter can still use it for early console |
| `NETCONSOLE` | the only log channel when the display is dead |
| `SND_SEQUENCER`, `SND_HRTIMER`, `SND_SEQ_DUMMY` | MIDI/sequencer, ~kilobytes |
| `USB_MON`, `USB_PRINTER`, `HIDRAW` | tiny; HIDRAW is used by some device tools |
| `CIFS`, `NFS_V4` extras | no SMB/NFS share in the current plan; easy to add as modules if that changes |
| `QUOTA`, `SCSI_SPI_ATTRS` | inherited from the defconfig, harmless |
