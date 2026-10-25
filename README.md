# Macbook5-1-Linux-Kernel

## linux-mbp51-extreme

One aggressively stripped, performance- and power-oriented custom Arch kernel for the late-2008 Apple MacBookPro5,1. Built in GitHub Actions with **no local WSL or Linux required**.

**STATUS: experimental. Baseline kernel and Broadcom compatibility compile
passed in hosted CI. A new source-locked Linux 7.4 development snapshot at
21a7f44fd076 is undergoing fresh validation. No physical MacBook boot has
yet been performed. Never install as the only bootable kernel.**

Upstream is pinned to a full Git SHA in [source.lock](source.lock). Our reviewed 7.4 development snapshot still identifies itself as **7.3.0** in its upstream Makefile, with a unique source-specific local version suffix. This is not a released or tagged 7.4 kernel.

### Tested laptop baseline

Core 2 Duo P8600 (2.4 GHz, Penryn, x86-64-v1 with SSE4.1), 8 GB RAM, NVIDIA MCP79, integrated 9400M (NVAC), discrete 9600M GT (NV96), Apple gmux and SMC, ADATA SU635 3 Gb/s SATA SSD, BCM4322 Wi-Fi using proprietary broadcom-wl DKMS, NVIDIA forcedeth Ethernet. MX Linux previously verified both Nouveau renderers, input, network and ACPI S3 suspend/wake.

### Decisions

- One combined slim/performance/power build; no competing custom kernel variants.
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
2. After merging the PR, merging to main triggers one build automatically; GitHub Actions > **Build experimental MBP5,1 kernel** > **Run workflow** is also supported.
3. The workflow downloads the pinned source, runs Kconfig resolution and audit, and invokes upstream kernel's maintained `make pacman-pkg` target to package both kernel and DKMS headers.
4. Download the artifact, verify checksums, and *only then* follow the cautious manual installation procedure.

### Layout

```text
.
├── .github/workflows/
│   ├── lint.yml
│   └── build-kernel.yml
├── AGENTS.md
├── source.lock
├── scripts/
│   ├── configure.sh
│   ├── audit-config.sh
│   ├── build.sh
│   └── lint.sh
├── runtime/
│   ├── systemd/mbp51-powertop.service
│   ├── systemd/zram-generator.conf
│   ├── system-sleep/50-mbp51-powertop
│   └── sysctl.d/99-mbp51-memory.conf
└── docs/
    ├── ENGINEERING.md
    ├── BUILD.md
    └── INSTALL.md
```

Important: CI passing means packages were built and audited, **not** that Broadcom STA has compiled for them or the Mac's Nouveau, gmux, sleep, or power policy has been hardware-verified.

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
`bash compat/broadcom/make-local-package.sh 7.3.0-mbp51-extreme-g21a7f44f`.
No vendor binary is published by our public CI. The boot image and module
package must share the exact `kernelrelease.txt` value. Installation is
deferred until the machine's boot partition and known-good recovery entry
are verified; see [INSTALL.md](docs/INSTALL.md). Read-only device evidence
is collected with `bash scripts/hardware-report.sh`.

### Direct SSD installation on the late-2008 MacBook

A fresh Arch installation can now be bootstrapped from the **official Arch
installer USB**, wiping the internal ADATA SU635 SSD with explicit user
authorization. See [fresh SSD install and macOS USB flashing](docs/FRESH-ARCH-INSTALL.md).

The **read-only** preflight is `bash install/archiso-install.sh --plan /dev/sda`.
The destructive action is separate and requires both the MacBookPro5,1 +
SU635 guard and a typed confirmation. The installer uses the stock Arch LTS
kernel first with an LXQt/Openbox X11 desktop; once LTS works, the matching
verified experiment is added by
`bash install/activate-custom-kernel.sh --install dist` as a manual GRUB
choice without changing the LTS default. Existing Arch installations should
use [the non-destructive custom-kernel installation guide](docs/INSTALL.md)
instead of the fresh-disk installer.
