# Local model handoff — MacBookPro5,1 kernel engineering

**Snapshot:** 2026-10-25. **Owner intent:** aggressively optimize a late-2008 dual-core MacBook Pro for responsiveness, useful battery life, and small footprint; preserve independently bootable Daily/BORE/Extreme experiments and **keep both GPUs available**. No personal files on the SSD need preserving, but **do not format the disk just because a wipe was allowed**: the existing Btrfs/EFI install passed read-only multikernel preflight and is a valuable recovery baseline.

**First read:** `docs/THREE-TIER-MULTIBOOT.md`, `docs/V2-HARDWARE-PLAN.md`, `docs/ENGINEERING.md`, `docs/DAILY-INDEPENDENT.md`, `source.lock`, `scripts/configure.sh`, `scripts/audit-config.sh`, `scripts/tier-profile.sh`, the kernel and Broadcom workflows. Those docs are plans, not guarantees that unimplemented tiers exist.

## Mission and decision rules for the local model

- Act as an engineering owner: review evidence, search original upstream kernel/driver history, explore concrete optimizations, implement small reviewable changes, test, and document measured tradeoffs. Challenge earlier guesses if source code or measurements disagree.
- Improve **interactive latency on two Penryn cores**, idle/suspend power, reliability, and boot/kernel size **without sacrificing sound, battery recognition, Broadcom Wi-Fi, GPU availability, Apple input, SMC thermals or LTS recovery**.
- **Tier 1** is the trustworthy daily baseline. **Tier 2** uses a *real* separately ported BORE scheduler, toggleable at runtime against EEVDF. **Tier 3** is a separate experimental codebase for voltage, deeper GPU and power sequencing, and advanced platform tweaks. Do not issue placebo binaries for absent patches.
- Distinguish proven observations from hypotheses. Never claim an improvement without reproducible before/after measurements; do not assume smaller kernel packages yield lower battery watts.
- Make no destructive installation, disk wipe, firmware flash, arbitrary clockgen/voltage writes, or automatic GPU rail-off. Any such action requires explicit owner authorization and a documented recovery path. Do not automatically alter the current GRUB default.
- User intentionally requested `CONFIG_CPU_MITIGATIONS=n`; this reduces speculative-execution defenses (Meltdown/Spectre etc.) and must remain explicitly noted, **not** confused with disabling normal userspace memory isolation, namespaces, seccomp, ACLs or thermal shutdown.
- Keep the owner's global `powertop --auto-tune` preference, but add narrowly scoped hardware exceptions for any USB/input, Broadcom, SATA or suspend regressions. Do not add TLP as a conflicting second policy engine.
- No `-march=native` when building on GitHub Actions: hosted runners have modern CPUs. P8600 supports SSE4.1 but lacks SSE4.2 and POPCNT; do not target the x86-64-v2 ISA. `-mtune=core2` with generic x86-64 is deliberate.

## Physical machine and measured v1 observations

| Component | Actual observed state |
|---|---|
| Host / OS | `chonkpro51`, `MacBookPro5,1`, EndeavourOS LXQt/Openbox X11, GRUB 2, Dracut, Apple EFI/SMC |
| CPU | Intel Core 2 Duo P8600, 2 cores / 2 threads, 2.40 GHz; ACPI P-states **2394/2128/1862/1596 MHz** |
| Idle / scheduler | `acpi-cpufreq` + `schedutil`, `PREEMPT_LAZY`, EEVDF; C3 heavily used, with C1/C2; 1000 Hz + `NO_HZ_IDLE` |
| Memory | 8 GiB; 4 GiB LZ4 ZRAM high-priority swap, ~8.8 GiB SSD swap fallback, MGLRU; v1 lacked `USER_NS/MEMCG/PSI` |
| Storage | ADATA SU635 SATA SSD, 223 GiB nominal; preflight: Btrfs volume 213 GiB, **6.9 GiB used / 205 GiB available**; Btrfs `/@`, `/@home`, zstd:3, `noatime`, `discard=async`; v1 kernel mounted `noacl` because `BTRFS_FS_POSIX_ACL=n` |
| GPUs | NVIDIA 9400M `03:00.0` drives internal panel, 9600M GT `02:00.0` remains powered; Nouveau, Apple gmux 1.7.3, `vga_switcheroo`. Prior MX Linux tested offload with glmark2 ~358 (9400M) / 520 (9600M) at 640x480; **recheck** on current EndeavourOS |
| GPU power | `vgaswitcheroo` reported `IGD:+:Pwr` and `DIS: :Pwr`; both PCI `power/control=on`, no runtime-suspended time; ~63°C integrated / ~65°C discrete in original capture (not controlled idle power data) |
| Display | `gmux_backlight` max 16138, actual ~2543; low-brightness flicker also occurs on stock kernel. No proof of a software fix. Nouveau/Xorg produces `drm_atomic_check_only` warnings in v1 |
| Audio | NVIDIA MCP79 HDA `00:08.0`, `snd_hda_intel` loads, **no ALSA soundcards** in v1 because `SND_HDA_CODEC_REALTEK=n` and `SND_HDA_GENERIC=n`; worked with stock kernel |
| Wi-Fi | Broadcom BCM4322 (PCI 14e4:432b) functional using patched proprietary Arch `broadcom-wl-dkms` module; binary must be built locally per kernel ABI, never checked into repo or publicly redistributed |
| Battery | `/sys/class/power_supply` exposes `ADP1` but **no BAT*** in v1; ACPI EC/BATTERY=y, PNP0C0A firmware device appears. `upower.service` failed systemd 217/USER and namespace setup error with USER_NS=n. ACPI_SBS support is being added as diagnostic, not guaranteed solution |
| Bluetooth | btusb endpoint enumeration warning; `bluetoothctl list` hung. Wrap all Bluetooth probes in `timeout -k 2 5` |
| Physical peripherals | Apple BCM5974 trackpad, Apple USB HID keyboard, webcam UVC, FireWire, MCP79 OHCI/EHCI USB, forcedeth Ethernet, applesmc fans and thermal sensors |
| v1 binary | `7.3.0-mbp51-extreme-g21a7f44f`, booted successfully; ~11 MiB kernel, ~146 MiB generic Dracut initramfs; never rely on `modinfo` spelling of `/lib` vs `/usr/lib` without realpath comparison |

On 2026-10-25 15:34 Phoenix time, user's read-only `scripts/multikernel-preflight.sh` reported:
- `linux 7.2.11.arch1-1`, `linux-lts 6.18.58-1`, and current `linux-mbp51-extreme 7.3.0_mbp51_extreme_g21a7f44f-1` packages.
- `/boot/vmlinuz-linux-lts`, `/boot/initramfs-linux-lts.img`, and `/boot/grub/grub.cfg` present; ESP `/boot/efi` vfat 2 GiB.
- GRUB_DEFAULT **explicitly** set to `gnulinux-advanced-a75e472c-72e1-4baf-a998-7f2afef7a651>gnulinux-linux-lts-advanced-a75e472c-72e1-4baf-a998-7f2afef7a651`; **do not substitute GRUB_DEFAULT=0**.
- Existing v1 boot files `/boot/mbp51/vmlinuz` and `/boot/mbp51/initramfs.img`; these are legacy paths, **not** safe to reuse for simultaneous tier installation.
- There is **no requirement to wipe**. User is willing if genuinely needed, but no benefit has yet been demonstrated.

## Pinned Linux and current GitHub implementation

Repository: https://github.com/hussmanne/Macbook5-1-Linux-Kernel

`source.lock`: upstream torvalds/linux commit
`21a7f44fd0765fcc5194130b28767786eba1d1e7` (October 25 2026),
archive SHA256 `1af6d999723ab2309946456e6a38953583a087c720be98295224e3ddbb384295`.
This is **post-v7.3 / 7.4 merge window**, but the Makefile labels `7.3.0`.
The pinned snapshot already includes October 2026 EEVDF work and merged sched_ext improvements; **sched_ext is not compiled in current minimal config** because BPF syscall/JIT/BTF were pruned.

Relevant history:
- PR #20: v2 fixes and LTS-guarded installer: https://github.com/hussmanne/Macbook5-1-Linux-Kernel/pull/20
- PR #21: three-tier design and multikernel preflight: https://github.com/hussmanne/Macbook5-1-Linux-Kernel/pull/21
- PR #22: independent Daily kernel code: https://github.com/hussmanne/Macbook5-1-Linux-Kernel/pull/22
- v2 kernel build GitHub Actions run **40240325040 succeeded**: https://github.com/hussmanne/Macbook5-1-Linux-Kernel/actions/runs/40240325040
- Static validation and installer compatibility for PR #22 **passed** at commit `680531f8` before final handoff/Broadcom changes; re-check latest PR head and run status.

Current legacy v2 includes:
`USER_NS=y`, `MEMCG=y`, `PSI=y`, `BTRFS_FS_POSIX_ACL=y`,
`SND_HDA_CODEC_REALTEK=m`, `SND_HDA_GENERIC=m`,
`SND_USB_AUDIO=m`, `ACPI_SBS=m`; legacy v2 ABI
`7.3.0-mbp51-extreme-g21a7f44f-v2`. No device has yet physically booted v2. Realtek, UPower, battery and Bluetooth fixes MUST be confirmed on physical MacBook. AMD P-state still resolves `=y` as an upstream Kconfig-selected symbol; it is irrelevant to this Penryn but do not claim it was disabled.

Independent Daily tier from PR #22:
- Profile `MBP51_TIER=daily`, `PACMAN_PKGBASE=linux-mbp51-daily`, headers `linux-mbp51-daily-headers`, `LOCALVERSION=-mbp51-daily-g21a7f44f-v1`.
- Private vendor module package `mbp51-broadcom-wl-daily`; unique `/usr/lib/modules/$release/updates/mbp51/wl.ko`, deps on `linux-mbp51-daily`.
- Build `dist/daily/`, separate kernel and headers package; separate GitHub Actions `.github/workflows/build-daily.yml` artifact `mbp51-daily-kernel-and-headers`.
- `install/activate-daily-kernel.sh --plan [DIST_DIR]` is read-only; `--install` installs packages, builds matching wl privately, creates `/boot/mbp51/daily/` hostonly/generic Dracut files, adds `/etc/grub.d/42_mbp51-daily` and manual GRUB entries, keeping explicit LTS default.
- `MBP51_TIER=legacy` keeps old scripts backward-compatible. `MBP51_TIER=bore` now has a locked source port, isolated package identity, artifact checks, and a build workflow, but is **not shippable** until CI compiles both the kernel and matching Broadcom module. `MBP51_TIER=lab` now has a real feature-preserving HZ=250 configuration profile, isolated package identity, installer, and build path; voltage/GPU-rail/firmware experiments remain outside this first bootable Lab profile. Never bypass missing evidence with fake artifacts.

### Known CI issue that must be checked, not concealed

Run **40241714467** (Broadcom wl DKMS compatibility) failed:
https://github.com/hussmanne/Macbook5-1-Linux-Kernel/actions/runs/40241714467.
The v2 package and header checksums **passed**, but `compat/broadcom/patch-broadcom-wl.py` still accepted only the **old v1** release, so it exited at:
`Unsupported locked development-kernel release: 7.3.0-mbp51-extreme-g21a7f44f-v2`.
This is **not** evidence that the patched driver cannot compile; compilation was never reached. Also the test installed only header files, causing DKMS complaints about an absent kernel modules tree. Follow-up changes in the handoff PR permit only the explicitly pinned legacy v2 and Daily ABIs and install the kernel alongside headers in the ephemeral test container. **Do not call Broadcom CI green until a new job completes.** The archived successful v1 test is not proof of v2 or Daily compatibility.

If a follow-up Broadcom workflow is required, test both artifacts independently. Arch `broadcom-wl-dkms` source is version 6.30.223.271; the repo's patcher strictly rewrites 18 nl80211 callback signatures, 2 ioctl ops, legacy work flush and targeted warnings. Never weaken exact-count guards simply to force a pass. All binaries are local-only.

## Independent tier matrix — release contract

| Tier | Role | Package ID | Kernel release | Boot dir |
|---|---|---|---|---|
| Stock LTS | Recovery | `linux-lts` | Arch package ABI | distro maintained |
| Legacy v1/v2 | Existing test | `linux-mbp51-extreme` | v1 installed / v2 CI build | `/boot/mbp51/` |
| **Daily** | Tier 1 EEVDF; most reliable | `linux-mbp51-daily` | `7.3.0-mbp51-daily-g21a7f44f-v1` | `/boot/mbp51/daily/` |
| **BORE** | Tier 2 scheduling research | `linux-mbp51-bore` | `7.3.0-mbp51-bore-g21a7f44f-bore7.0.0-r1` (CI pending) | `/boot/mbp51/bore/` |
| **Lab** | Tier 3 feature-preserving HZ=250 experiment | `linux-mbp51-extreme-lab` | `7.3.0-mbp51-lab-g21a7f44f-lab-hz250-r1` (CI pending) | `/boot/mbp51/lab/` |

Four core boot targets (LTS + Daily/BORE/Lab) plus separately preserved legacy. Each custom tier needs isolated kernel+headers, source/patch provenance, external Broadcom package, Dracut host-only primary and generic fallback, unique GRUB ID. Package file-list collision test **before install**. No package ownership overlap; don't rely on a renamed menu entry alone.

## Immediate to-do list — in order, with verification criteria

1. **Repo state and CI:** `git fetch origin && git status --short && git log --oneline -8`; inspect latest `main`, merged PR state, Actions results. Do not overwrite another agent's edits. Run `bash scripts/lint.sh`, `bash scripts/test-tier-profiles.sh`, `bash scripts/test-verify-artifacts.sh`, pinned Kconfig legacy+Daily+BORE+Lab. Fix Broadcom CI if needed, and confirm v2 + Daily + BORE + Lab builds produce distinct valid archives without collision.
2. **LTS hardware comparison:** Boot **linux-lts** and capture `scripts/compare-kernels.sh`. Capture analogous v1/v2 data. Compare presence of `BAT*/power_supply`, AC adapter online, `PNP0C0A:00`, `upower.service`, AL(S)A codec and physical playback, Bluetooth, Nouveau warnings, USB endpoint status, gmux, backlight values, suspend/resume. The owner has not yet supplied the LTS comparison; absence of BAT* in v1 alone is not proof of battery failure. Never run an unbounded `bluetoothctl list`.
3. **Tier 1 physically qualify:** Obtain Daily artifact only after successful build+hash validation, `install/activate-daily-kernel.sh --plan dist/daily`, check LTS default and entire installer script carefully before `--install`. Verify Wi-Fi driver `vermagic` against exact ABI, HDA audio playback/capture, Btrfs ACL, PSI+MEMCG, battery, SMC fans, network, suspend/resume, on-demand 9600M. No claim of production-ready until all pass on-device.
4. **Dual GPU as independent modes:** check `xrandr --listproviders`, `glxinfo -B`, `DRI_PRIME=1 glxinfo -B`, DRM device owners, `vga_switcheroo` state and Nouveau pm behavior. Aim for LCD on 9400M + optional 9600M render/offload, OR controlled logout/reboot into gmux discrete mode if offloading doesn't work. Confirm GPU `OFF` genuinely removes rails; test `ON`/resume repeatedly before any persistent power-off. No automatic use of `MIGD`/`MDIS` or blind offlining. User explicitly wants to retain ability to use faster GPU.
5. **BORE v7.0.0 source port:** the local port now targets the exact pinned upstream snapshot with locked provenance, the futex accessor adaptation, runtime `kernel.sched_bore` toggle, and default-off EEVDF behavior. The remaining gates are source-level compile/Kconfig validation, matching Broadcom DKMS compilation, package collision checks, and physical comparison. Do not claim 7.4 scheduler improvements necessarily compatible without examining conflicts. Evaluate interactive p95/p99 latency under two-core saturation, compile and compression throughput, thermals, power, context switches. Keep 1000 Hz and all other workload settings fixed in the first BORE A/B.
6. **Extreme Lab branch:** The first Lab profile is now a real HZ=250 configuration experiment that preserves the v1-recovered audio, userspace, ACL, battery/SMC, Wi-Fi, input, thermal, and GPU features. Boot and compare it against legacy/Daily/BORE only after CI artifacts pass. Penryn PHC-style undervolt may be explored later, but modern mainline cpufreq does not expose reliable PHC VID modification. Research the historical driver and actual P8600 VID/VRM specifics before coding. Boot stock voltage; opt-in, bounded per-P-state undervolt only; require computational correctness tests, checksum validation, heat/suspend testing, and power recovery. No arbitrary raw MSR writes, clockgen flashing, BCLK overclock or permanent frequency caps. If infeasible, **state infeasible**, do not fake a voltage gain.
7. **Power and size:** profile `powertop` idle wakeups, SMC temps/fan RPM, CPU idle state residency, battery `power_now` if available or external power meter; tune PCIe ASPM only on supported links, selective USB autosuspend, SATA `med_power_with_dipm` only with SSD data-integrity checks, HDA power save after restoring codec; remove actually unused userspace services and kernel features. Favor battery savings from unused discrete GPU over byte-scale driver pruning. Compare baseline 1000 Hz vs 250 Hz *separately*; avoid simultaneously modifying scheduler, frequency governors and graphics. Keep host-only Dracut with generic fallback.
8. **Brightness:** `gmux_backlight` flickers at low levels on stock and custom, so verify whether Xorg Nouveau dithering versus PWM driver behavior causes it; reversible dithering test can be useful. A minimum brightness of zero is not promised to turn panel off: use DPMS to request panel off; inspect resume. Direct LP8543 PWM register manipulation is laboratory-only and must not occur automatically.

## Benchmark and acceptance harness to implement

Build `scripts/benchmark/{baseline,compare,ui-load,validate}.sh` or equivalent:
- Capture immutable SHA, CONFIG, boot cmdline, microcode, ambient/thermal state, AC vs battery, governor/P-state limits, GPU active driver/rails, loaded modules, services and power profile.
- Consistent idle settling conditions and repeatable two-core mixed workloads; samples of p50/p95/p99 UI latency, CPU throughput, total task completion time, context switches, CPU idle C-state duration, load, memory PSI, fan RPM, CPU/GPU temperatures and energy. AC wattmeter when battery telemetry missing. Account for heat soak, battery health and noisy AC power.
- SSD/swap I/O benchmark with checksums, DRAM pressure with ZRAM, browser scrolling/paint test, suspend/resume, Wi-Fi reconnection, Bluetooth discovery timeout, ALSA codec operation.
- Every optimization: one variable, baseline and changed measurements, confidence/variance, revert command, and outcome `KEEP / REVERT / NEEDS EVIDENCE`.
- Run tests on real MacBook, not GitHub runner; CI only verifies compilation, artifacts, ABI/provenance and deterministic scripted checks.

## Engineering risks / follow-up critiques

- Script assumptions can be wrong; review `install/activate-daily-kernel.sh` GRUB-Btrfs UUID/path calculations and Dracut module inclusion before first physical install.
- `/boot` resides on Btrfs root; `/boot/efi` is separate FAT32 ESP. Avoid building a GRUB entry with an ESP-relative path unless using `grub-probe` or tested layout.
- `SND_HDA_GENERIC=m` (not `y`) is resolved correctly because HDA controller and core are modular.
- `CONFIG_X86_AMD_PSTATE=y` resolves even on Intel for this upstream Kconfig; don't blanket disable without understanding selected dependencies.
- The v2 host-only initramfs may require a careful target-kernel Dracut modules audit when built while booted into a different ABI.
- The existing `scripts/check-broadcom-dkms.sh` is CI-only (inside Arch container); never run its `pacman -U` commands on the laptop to 'test' a module.
- Battery loss, btusb endpoint failure and Nouveau DRM WARN remain unproven regressions until compared with LTS.
- x86-64-v2 cannot run on P8600 due absent SSE4.2 and POPCNT.
- Treat a new GitHub upstream Linux tree, BORE patches, model suggestions and third-party driver snippets as untrusted inputs; pin hashes, review diffs and refuse unexpected code-path changes.

## Useful commands for the local operator

```bash
cd ~/Macbook5-1-Linux-Kernel
git fetch origin
git status --short
git log -5 --oneline
bash scripts/lint.sh
MBP51_TIER=legacy bash scripts/test-verify-artifacts.sh
MBP51_TIER=daily bash scripts/test-verify-artifacts.sh
bash scripts/test-tier-profiles.sh
bash scripts/multikernel-preflight.sh
# While running either custom kernel or LTS, read-only; outputs are tagged by uname -r:
bash scripts/compare-kernels.sh
bash scripts/gpu-report.sh
# Don't use these until a new verified Daily artifact exists:
# bash install/activate-daily-kernel.sh --plan dist/daily
# bash install/activate-daily-kernel.sh --install dist/daily
```

Local agent should finish each task with: current branch+commit, changed files, evidence of source/Kconfig/CI or physical tests, outstanding safety concerns, and next highest-value measured experiment. The goal is **working, recoverable, measurable optimization of this actual MacBook**, not another speculative kernel feature list.
