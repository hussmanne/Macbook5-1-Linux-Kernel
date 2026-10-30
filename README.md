# Macbook5-1-Linux-Kernel

## MacBookPro5,1 kernel tiers

Independently packaged, performance- and power-oriented Arch kernels for the
late-2008 Apple MacBookPro5,1. Built in GitHub Actions with **no local WSL or
Linux required**.

**STATUS: experimental.** Daily upstream EEVDF, BORE, the feature-preserving
Extreme Lab profile, and the legacy corrective kernel have separate
package/module/boot identities. Hosted CI is the compile and provenance gate;
physical boot testing is intentionally multi-kernel. Never remove LTS or test
an experimental tier as the only bootable kernel.

All three tiers are built from **one** hardware profile
([docs/KCONFIG-PROFILE.md](docs/KCONFIG-PROFILE.md)): same source pin, same
`.config`, same installer, same Broadcom tooling. Resolved from
`scripts/configure.sh`, Daily-vs-BORE differs by two configuration symbols and
Daily-vs-Lab differs by two. They separate *experiments*, not *risk* — `linux-lts`
is the only independent fallback on the machine. The tier list, the ABI strings
and the boot-probability analysis are in
[docs/REVIEW-2026-10-29.md](docs/REVIEW-2026-10-29.md). Where the battery life
actually goes, and why almost none of it is a kernel option, is in
[docs/POWER-PERF-2026-10-29.md](docs/POWER-PERF-2026-10-29.md).

Configuration revision `c2` trims what cannot exist on a MacBookPro5,1
(virtio/9p guest stack, eight unused NICs, PCCARD, NUMA, i915, AGP,
`SCHEDSTATS`, `KALLSYMS_ALL`) and restores what an EndeavourOS desktop needs but
`x86_64_defconfig` omits (framebuffer console, nf_tables, FUSE, overlayfs,
AppArmor, BPF, `coretemp`, Apple IR). Every ABI string is derived from
`source.lock`; nothing hard-codes a version.

Upstream is pinned to a full Git SHA in [source.lock](source.lock). Our reviewed 7.4 development snapshot still identifies itself as **7.3.0** in its upstream Makefile, with a unique source-specific local version suffix. This is not a released or tagged 7.4 kernel.

### Tested laptop baseline

Core 2 Duo P8600 (2.4 GHz, Penryn, x86-64-v1 with SSE4.1), 8 GB RAM, NVIDIA MCP79, integrated 9400M (NVAC), discrete 9600M GT (NV96), Apple gmux and SMC, ADATA SU635 3 Gb/s SATA SSD, BCM4322 Wi-Fi using proprietary broadcom-wl DKMS, NVIDIA forcedeth Ethernet. MX Linux previously verified both Nouveau renderers, input, network and ACPI S3 suspend/wake.

### Source terminology

The source lock is a post-v7.3 Linux development snapshot in the v7.4 merge
window. Its upstream Makefile still reports `7.3.0`; this repository does not
call it a released Linux 7.4 kernel. **BORE 7.0.0 is the BORE scheduler
project's release number, not a Linux 7.0 kernel.** The BORE patch targets
Linux 7.3-rc2 and is carried as a reviewed port onto the pinned post-v7.3/v7.4
development source.

### Decisions

- Daily is the upstream-EEVDF reference. BORE is a separate scheduler
  alternative. Extreme Lab is a real feature-preserving HZ=250 configuration
  experiment that keeps the features recovered after v1; voltage, GPU rail,
  and firmware experiments remain separate and are not hidden in this profile.
- User-directed **CONFIG_CPU_MITIGATIONS=n**. This deliberately removes optional CPU speculative-execution side-channel protections; cannot be reversed with a boot flag.
- Hardware family trimming, no heavy debug/sanitizer builds; retain DEBUG_FS, FTRACE and PERF_EVENTS for PowerTOP and vga_switcheroo.
- Upstream EEVDF with lazy dynamic preemption, NO_HZ_IDLE, 1000 Hz tick
  (this upstream tree lacks 500 Hz), schedutil on ACPI cpufreq, 2-CPU maximum,
  MGLRU and a true LZ4-enabled zram backend.
- Reapply **global powertop --auto-tune** after boot and wake. This may affect peripheral reliability; it is a user-requested aggressive policy.
- Do **not** automatically cut GPU power, force PCIe ASPM, or use risky SATA link policies until tested on the real machine.
- Retain the existing stock Arch kernel and bootable recovery media.

### Build and install

1. Review [Engineering specification](docs/ENGINEERING.md), [build procedure](docs/BUILD.md), and [installation/rescue instructions](docs/INSTALL.md).
2. The legacy, Daily, BORE, and Extreme Lab workflows build independently.
   Daily uses upstream EEVDF; BORE applies the locked scheduler port; Lab
   applies the locked feature-preserving HZ=250 configuration profile.
3. Each workflow downloads the pinned source, runs Kconfig resolution and
   audit, and invokes upstream kernel's maintained `make pacman-pkg` target to
   package both kernel and DKMS headers.
4. Download the artifact, verify checksums, and *only then* follow the cautious manual installation procedure.

For the actual experiment, keep LTS plus at least three independent custom
boot entries: Daily, BORE, and Extreme Lab. See
[the Lab boot-test matrix](docs/EXTREME-LAB-BOOT-TEST.md).

### Layout

```text
.
├── .github/workflows/
│   ├── lint.yml
│   ├── build-kernel.yml
│   ├── build-daily.yml
│   ├── build-bore.yml
│   └── build-lab.yml
├── AGENTS.md
├── source.lock
├── scripts/
│   ├── configure.sh
│   ├── audit-config.sh
│   ├── build.sh
│   ├── apply-tier-patches.sh
│   └── lint.sh
├── patches/
│   ├── bore.lock
│   └── lab.lock
├── runtime/
│   ├── systemd/mbp51-powertop.service
│   ├── systemd/zram-generator.conf
│   ├── system-sleep/50-mbp51-powertop
│   └── sysctl.d/99-mbp51-memory.conf
└── docs/
    ├── ENGINEERING.md
    ├── BUILD.md
    ├── INSTALL.md
    ├── KCONFIG-PROFILE.md
    ├── INSTALL-RUNBOOK.md
    └── REVIEW-2026-10-29.md
```

Important: CI passing means packages were built and audited, and the matching
Broadcom STA build passed its own job when that job is green. It still does
**not** prove the Mac's Nouveau, gmux, sleep, scheduler behavior, battery,
audio, or power policy has been hardware-verified.

### External Broadcom Wi-Fi compatibility

After every successful kernel build, a separate read-only runner validates the
maintained Arch `broadcom-wl-dkms` package against exactly the published kernel
headers. This is a compile/link check, **not** a device scan or connectivity
guarantee. See [Broadcom qualification](docs/BROADCOM.md).

The on-device [Broadcom build-only helper](compat/broadcom/build-on-device.sh)
can compile the source-locked patch in a private directory without overwriting
the Arch-maintained Broadcom source or automatically loading the module.
This is separate from first-boot qualification.

### Reproducible Wi-Fi installation and safe first boot

The patched proprietary Broadcom module can now be compiled **locally** and
packaged as a normal, version-locked `mbp51-broadcom-wl` Arch package:
`bash compat/broadcom/make-local-package.sh 7.3.0-mbp51-extreme-g21a7f44f-v2-c2`.
No vendor binary is published by our public CI. The boot image and module
package must share the exact `kernelrelease.txt` value. Installation is
deferred until the machine's boot partition and known-good recovery entry
are verified; see [INSTALL.md](docs/INSTALL.md). Read-only device evidence
is collected with `bash scripts/hardware-report.sh`.

### One-command MX hardware survey

Before changing the installed MX kernel, use the GitHub Actions workflow
**Package MX hardware survey**. Its `mbp51-hardware-survey` artifact contains
one portable program that captures the complete hardware/configuration
inventory plus bounded idle and CPU-load measurements, including battery power,
interrupts, idle-state residency, CPU frequency behavior, thermals, GPUs,
audio, Wi-Fi, Bluetooth, storage, ACPI, and raw evidence. See
[the survey guide](docs/HARDWARE-SURVEY.md).

### Direct SSD installation on the late-2008 MacBook

**Current recommended route: EndeavourOS Titan Nova via the official Calamares
installer.** Create the USB on Windows with Rufus in DD mode, then choose
online installation, LXQt, GRUB, and unencrypted Btrfs to the ADATA SU635
internal SSD. The user has approved erasing the existing APFS/macOS data.

After first boot into EndeavourOS, install and verify the regular LTS
kernel as an independent fallback, and then use the new **EndeavourOS
dracut activation helper** to install our separately compiled
7.4-development kernel and the locally adapted proprietary Broadcom module.
See [EndeavourOS installation and custom-kernel handoff](docs/ENDEAVOUROS-INSTALL.md).

A custom **vanilla Arch ISO** automation remains available as an alternative
at [fresh Arch installation](docs/FRESH-ARCH-INSTALL.md) and
`install/archiso-install.sh`, but its mkinitcpio-oriented activation
helper is **not** appropriate for EndeavourOS's default dracut setup.
No experimental kernel has been physically booted on the MacBook yet.
