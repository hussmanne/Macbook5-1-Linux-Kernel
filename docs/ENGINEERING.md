# linux-mbp51-extreme: full engineering contract

## Objective

Design one custom rolling-compatible Linux kernel for a late-2008 MacBookPro5,1:
minimize irrelevant drivers and instrumentation, prioritize short interactive
tasks on two Penryn cores, exploit CPU sleep states, compress memory efficiently,
preserve working dual-NVIDIA rendering and Apple-specific hardware, and apply
aggressive whole-system PowerTOP tuning. No multi-kernel optimization matrix.

The machine is a laptop and power efficiency matters as much as throughput.
Removing dormant modules saves build/storage size more reliably than energy.
Do not disable ACPI, S3, cpufreq, cpuidle, thermal protection or runtime PM.

## Directly observed hardware

- Apple MacBookPro5,1, 15-inch late 2008; Apple EFI + SMC.
- Intel P8600 Penryn at 2.4 GHz; two cores/two threads; x86-64-v1 baseline
  despite supporting SSE4.1; no SSE4.2, POPCNT or AVX.
- 8 GB installed RAM.
- NVIDIA MCP79 chipset; GeForce 9400M/NVAC PCI 03:00.0 (internal display),
  GeForce 9600M GT/NV96 PCI 02:00.0 (PRIME offload); Apple gmux 1.7.3.
- ADATA SU635 SATA SSD negotiated at 3 Gb/s; SMART passed, TRIM supported.
- Broadcom BCM4322 PCI 14e4:432b; MX driver 'wl'; ensure external DKMS
  build works against custom headers before depending on wireless.
- MCP79 forcedeth Ethernet; HDA ALC889A audio; Apple BCM5974 trackpad,
  Apple HID keyboard, Apple SMC, brightness/ambient sensor; UVC webcam;
  internal USB Bluetooth; OHCI/EHCI USB and optional expansion; FireWire.
- MX Linux 25.3 kernel 6.12.107 Nouveau GL acceleration and successful ACPI S3
  suspend/resume. glmark2 at 640x480: 9400M score 358; offloaded 9600M
  score 520. Nouveau TRAP_PROP faults during GStreamer scanning; missing
  video decoder firmware. Neither issue can be marked fixed from CI.

## Source and upstream integration

Pin an immutable SHA from the official torvalds/linux tree in source.lock.
At first pin, the development branch is post-Linux 7.3 while its Makefile still
states 7.3.0. Call it post-v7.3 / 7.4 development, not a 7.4 release.
All modifications are deterministic scripts, not manual menuconfig edits.
Kconfig script changes + final .config and compiler metadata must accompany
the binary packages. Update source only via reviewed source.lock commit.
No opportunistic grafting of stale CachyOS/BORE patches: conflict and
provenance management take priority. Upstream EEVDF is the baseline,
with tick/preemption choices inspired by low-latency kernel builds.

## One configuration

Generic x86-64 GCC output at first: Intel Penryn cannot run x86-64-v2/v3
binaries. Avoid blindly using -march=native from a newer CI CPU or -O3.
Target CONFIG_HZ_500, CONFIG_NO_HZ_IDLE, CONFIG_PREEMPT_DYNAMIC (where
supported) and the regular upstream scheduler. Preserve high-resolution
timers, SMP, ACPI CPU_FREQ, CPU_IDLE and thermal management.

Strip unused DRM families, unrelated WLAN stacks, nonapplicable server buses,
virtualization host features, debug info, BTF, KASAN/KCSAN/UBSAN, heavy lock
debugging, crash debugger, unused instrumented tracing modes. Do not strip
CONFIG_DEBUG_FS, CONFIG_PERF_EVENTS, the minimum FTRACE facilities,
CONFIG_MODULES, matching external module headers, EFI, ACPI, SATA/SCSI layer,
USB 1.1/2.0/3.0, Nouveau, DRM, gmux, vga_switcheroo, forcedeth, Apple
input/sensors, camera, sound, Bluetooth, FireWire, ext4, Btrfs and FAT/VFAT.
Keep modern userspace sandboxing/cgroups/namespaces even though CPU mitigations
are omitted. Do not use localmodconfig as sole source of required devices.

### User-directed speculative execution security reduction

Set CONFIG_CPU_MITIGATIONS=n in the source configuration. This intentionally
removes optional defenses against applicable speculative-execution information
leakage (e.g. Spectre, Meltdown). Cannot restore at runtime. This does not
permit disabling ordinary userspace isolation, seccomp, filesystem ownership,
KASLR or thermal protection. README, manifests and recovery docs state risk.

## Runtime power/memory plan

Keep global powertop --auto-tune on boot and after S3 resume; record real
USB/SSD/Wi-Fi problems before adding narrowly scoped exceptions. The global
setting may suspend peripherals and can interfere with audio, Wi-Fi or storage
power policies; do not assert it is safe just because the kernel compiles.
Do not run TLP concurrently as an overlapping power manager. Avoid blind
pcie_aspm=force, unsafe SATA aggressive ALPM, disabling interrupt timers, or
automatic vga_switcheroo discrete-rail power-off.

Memory: MGLRU, supported ZRAM and LZ4; userspace zram-generator creates up to
4 GiB of logical compressed swap, swappiness 100, page-cluster 0. No disk
hibernation: suspend-to-RAM already worked in MX. No promise of improved power
from compressed swap when RAM is not pressured.

SSD: preserve NCQ/AHCI/TRIM, use weekly fstrim after installation, sensible
mq-deadline initial I/O scheduler. Btrfs snapshots/optional zstd:1 may be
tested in userspace. Kernel compilation cannot change SATA's 3 Gb/s negotiated
link rate.

## Packaging, CI and recovery

Build entirely on GitHub public Ubuntu x86-64 runner inside Arch container.
Standard runner currently lists 4 vCPU / 16 GB RAM / 14 GB SSD: reclaim unused
preinstalled tools, minimize debug builds and avoid full git history. Download
GitHub tarball by pinned upstream commit, record its actual sha256. Use
upstream's make pacman-pkg with PACMAN_PKGBASE=linux-mbp51-extreme and
PACMAN_EXTRAPACKAGES=headers, ensuring matching external-module build headers.
The Linux tree's maintained install-extmod-build script is preferred to manual
headers assembly. Two distinct Arch packages and a resolved .config are the
deliverables. Do not override stock 'linux' provides.

Static PR CI is read-only; kernel builds run on trusted pushes to main or
manual workflow_dispatch from the default branch. Do not run privileged code on untrusted public PRs or
automatically publish to an update channel. Never report a package as MacBook-
validated from hosted CI. First install retains stock Arch kernel, headers,
known-good bootloader and wired recovery. Actual test must include nouveau
rendering, wl DKMS, keyboard/trackpad, SMC temperatures, storage errors,
sound, camera, Ethernet, manual/lid S3 suspend/resume and power usage.

## Required failure behavior

If any Kconfig mandatory option fails to resolve, kernel source is unavailable,
the native upstream packaging changes, package names do not match, the two
expected artifacts are absent, or CI disk resources are exhausted, fail loudly.
No hidden fallback that re-enables CPU mitigations, removes hardware, or
silently produces a kernel package without headers.

## Pending work after initial CI build

Verify Broadcom wl DKMS module compilation against custom headers; develop an
on-device GPU power-off safety procedure; evaluate video decoding firmware
without assuming a driver workaround; measure overnight suspend drain and
real battery watts; create installation-mode-specific initramfs/GRUB commands
only after identifying the final filesystem and boot layout; verify all
PowerTOP tunables on the MacBook. Avoid calling these items complete.
