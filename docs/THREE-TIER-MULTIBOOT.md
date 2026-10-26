# MacBookPro5,1: three-tier Linux kernel system and multiboot contract

Status: **architecture plus independent build paths**, with physical boot still
required before any tier is trusted.
No automatic formatting/partitioning, GPU power switching, undervolting or
kernel activation is authorized by this document. A physical MacBook boot
is the mandatory final gate. Source snapshot initially uses the pinned
post-v7.3 / Linux 7.4-development commit 21a7f44fd076; kernel Makefile
currently says 7.3.0. Every variant must record source hash + patchset hash.

## Observed machine

- Apple MacBookPro5,1, Intel Core2 Duo P8600 Penryn 2 cores / 2 threads,
  2394/2128/1862/1596 MHz, C3 works, 8 GiB RAM, Mac EFI, SMC.
- NVIDIA MCP79 chipset, GeForce 9400M (03:00.0) LCD active and GeForce
  9600M GT (02:00.0) powered but not display-active; Nouveau and gmux 1.7.3.
  MX Linux observed PRIME glmark2 640x480 scores ~358 vs ~520 respectively,
  but repeat with current userspace to verify dynamic offloading.
- Broadcom BCM4322 14e4:432b works only with pinned-source patched
  proprietary wl.ko; must build a separate matching private module for
  EACH kernel ABI, never publish vendor blobs.
- MCP79 HDA Realtek ALC889A, BT over USB OHCI/EHCI, Apple trackpad,
  camera, FireWire; 223 GiB ADATA SU635 SATA SSD.
- Original custom Linux 7.4-development boot worked for graphics,
  Wi-Fi, Btrfs, ZRAM; missing HDA Realtek codec, CONFIG_USER_NS,
  MEMCG/PSI, Btrfs ACL; battery BAT* absent; audio and UPower fail.
- gmux_backlight max=16138; visible low-brightness flicker ALSO on
  stock kernel; cannot promise kernel PWM fix. DRM atomic Xorg warnings.
- Existing EndeavourOS already has GRUB+Dracut, EFI FAT32 /boot/efi,
  Btrfs /@, boot under /boot on Btrfs, stock linux and linux-lts.

## Four persistent GRUB boot targets (not kernel replacements)

1. linux-lts: known-good recovery. **Keep default until tier1 is proven**.
2. MBP51 Daily: linux-mbp51-daily, modules and headers private to daily.
3. MBP51 BORE: linux-mbp51-bore, isolated headers/modules/patch provenance.
4. MBP51 Extreme: linux-mbp51-extreme-lab, isolated headers/modules.

Future packaging MUST use unique PACMAN_PKGBASE values:
  linux-mbp51-daily | linux-mbp51-bore | linux-mbp51-extreme-lab

DO NOT use the legacy shared 'linux-mbp51-extreme' package name:
installing a new version removes prior version's files and can replace
/usr/lib/modules even though the GRUB menu appears to keep both.

Unique LOCALVERSION per tier (for a fixed source_sha):
  -mbp51-daily-g<SHA8>
  -mbp51-bore-g<SHA8>-<PATCHREV>
  -mbp51-lab-g<SHA8>-<PATCHREV>

Unique boot folders:
  /boot/mbp51/daily/vmlinuz and initramfs.img + initramfs-fallback.img
  /boot/mbp51/bore/vmlinuz and initramfs.img + initramfs-fallback.img
  /boot/mbp51/lab/vmlinuz and initramfs.img + initramfs-fallback.img

Explicit GRUB IDs:
  mbp51-daily, mbp51-bore, mbp51-extreme-lab, plus *-fallback variants.

Use an explicit versioned LTS GRUB menu ID as GRUB_DEFAULT, NOT index 0.
All custom entries are manual. Verify grub-script-check, dracut images,
matching wl vermagic, packager conflict check and boot path UUID/subvolume.
Each private Broadcom package must have unique `pkgname` and dependency
matching its distinct custom kernel. No automatic update to another tier.

## Tier 1 — Best-guess Optimized Daily

Target upstream EEVDF from pinned post-7.3/7.4-development commit, lazy
preemption, schedutil, 1000 Hz NO_HZ_IDLE until measured. Retain Btrfs,
USB, all real hardware, ACPI, GMUX, both Nouveau GPUs, working PowerTOP
metrics, audio HDA Realtek+generic, USER_NS, MEMCG, PSI, Btrfs ACL, SBS
for diagnostic, Apple SMC battery/thermal support. CPU tuning -mtune=core2
only, NR_CPUS=2, 4 GiB LZ4 zram priority high, SSD swap fallback,
MGLRU, no concurrent zswap. Preserve current CPU-mitigation policy
explicitly as a security risk. No unexpected kernel debug instrumentation.
Host-only Dracut primary and fully generic recovery image.
PowerTOP --auto-tune with verified exceptions, NOT blind power-off of GPUs,
storage or input. Dual GPUs remain supported. Do NOT claim fix for
missing BAT* merely because userspace UPower can start.

## Tier 2 — BORE Responsive Experimental

Everything tier1 needs to be functional, including both NVIDIA GPUs and
private Broadcom. The current local BORE v7.0.0 port targets the EXACT pinned
7.4-development source (kernel/sched/fair.c changed) in an isolated locked
patch series; it records provenance and fails on unresolved hunks. BORE's
optional runtime sysctl `kernel.sched_bore` (0=EEVDF-style behavior, 1=BORE)
is compiled in but initially default off. CI compilation, matching Broadcom
compatibility, and physical qualification remain release gates.
No claim of performance until input-latency, fork-heavy and throughput
stress pass. No sched_ext/BTF burden in this tier by default. Experiment
250Hz HZ versus 1000Hz only if a benchmark justifies it; don't change
both scheduler and HZ before obtaining comparable results. GPU switching
and power profile are runtime policies, not tier-unique blacklists.

## Tier 3 — Extreme Hardware Lab

Opt-in, untrusted for everyday computing. The first real Lab artifact is a
feature-preserving HZ=250 configuration experiment, keeping the recovered
audio, USER_NS, MEMCG, PSI, Btrfs ACL, battery/SMC, Broadcom, input, thermal,
and dual-GPU paths. It is intentionally separate from Daily and BORE so the
owner can boot at least three custom kernels plus LTS and compare them.

Later Lab revisions may include carefully reviewed PHC-style Penryn undervolt
controls on stock voltage by default; a per-AC/per-battery VID profile only
when validated with full thermal, CPU, memory, SSD checksum, and suspend/resume
stress. No raw MSR writes or flashing Apple firmware under an automated boot
script. No BCLK overclock promise. Optional GPU rail-off, PWM characterization,
and SATA ALPM remain measured follow-on experiments, not hidden defaults.
Keep EFI boot, thermal trips, SMC sensors, PM_SLEEP, ACPI EC, safe SSD ALPM,
and absolute LTS recovery.

## GPU modes are INDEPENDENT of kernel tiers

Default low-power: 9400M LCD, only cut 9600M rails if first test proves
switcheroo power state OFF, repeated ON recovery, and suspend/shutdown.
Performance: re-enable 9600M, either DRI_PRIME=1 on a verified X provider
configuration or gmux `DDIS`/switch requiring Xorg logout/restart/reboot.
No auto OFF at boot until reliable re-enable is demonstrated. Don't
blindly write `MIGD`/`MDIS`: these can create a black screen. Inspect
/dev/dri holders and `xrandr --listproviders` first. Backlight DPMS OFF
is not the same as gmux brightness zero.

## Optional clean SSD install (user authorizes wipe, not yet executed)

Choose EndeavourOS LXQt+Openbox X11, Btrfs root @ and @home, Dracut
and GRUB; retain FAT32 ESP of roughly 1-2 GiB; 4 GiB LZ4 ZRAM in RAM,
~8 GiB disk swap as lower-priority fallback (not hibernate); no need
for 4 partitions / OS installations. 223 GiB SSD has ample space for
all four kernels, initramfs pairs and small snapshots. Enable zstd:1
as experiment, not proven improvement over current zstd:3; prefer
noatime and measured TRIM. Create a GRUB recovery entry BEFORE
installing any experiment. No wiping needed to implement this scheme,
so avoid unnecessary reinstallation until all packages exist.

## CI / release gates (one independent kernel artifact per tier)

1. One pinned source lock and tier-specific reproducible config +
   patch hash. Unique PACMAN_PKGBASE, matching headers and local
   Broadcom package. No kernel file ownership overlap.
2. CI `olddefconfig` + assertions for ALL required features, and
   package file list cross-comparison. BORE patch clean-apply gate,
   compilation, sched_bore sysctl presence in resolved test artifacts;
   lab voltage code requires separate probe and tests.
3. GitHub Actions may matrix-build tiers once each passes source-level
   gating; never publish incomplete tiers as working.
4. On-device stock LTS comparison and Tier1 smoke test: BAT*, ALSA
   playback, UPower, Bluetooth, Wi-Fi, sensors, both GPU renderers,
   backlight control, Btrfs permissions, suspend/resume, DRM warnings.
5. Tier2 paired run 0/1 BORE with Firefox/UI latency while both cores
   saturated, compilation throughput, stability and power.
6. Tier3 only after reverting safely to stock P-state voltage and
   recovering from intentionally induced faults. Track temperature and
   checksum integrity. Never depend on a defective battery to quantify
   power use. Use AC-side measurements if needed.

## References

- Kernel VGA switcheroo / Apple gmux: https://docs.kernel.org/gpu/vga-switcheroo.html
- 7.4 scheduler pull: https://lists.openwall.net/linux-kernel/2026/10/18/476
- BORE source/patches: https://github.com/firelzrd/bore-scheduler
- Arch dracut: https://man.archlinux.org/man/dracut.8.en
