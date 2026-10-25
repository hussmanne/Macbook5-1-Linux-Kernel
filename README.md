# Macbook5-1-Linux-Kernel

## linux-mbp51-extreme

One aggressively stripped, performance- and power-oriented custom Arch kernel for the late-2008 Apple MacBookPro5,1. Built in GitHub Actions with **no local WSL or Linux required**.

**STATUS: experimental. The pinned kernel and matching Arch package pair compiled
on GitHub Actions on October 25, 2026, but the initial upload was blocked by
nonportable checksum paths. The follow-up packaging fix is being validated.
Not yet booted or tested on the MacBook. Never install as the only bootable kernel.**

Upstream is pinned to a full Git SHA in [source.lock](source.lock). At that snapshot the post-v7.3 Linux development tree still identifies itself as **7.3.0** in its Makefile. This is not a released or tagged 7.4 kernel.

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
