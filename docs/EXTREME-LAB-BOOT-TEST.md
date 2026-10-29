# Extreme Lab boot-test matrix

The Lab tier is a real bootable experiment, not a placeholder. Its first
profile changes one major scheduler variable—`HZ=250`—while retaining the
hardware and userspace features recovered after the original v1 attempt.
Voltage writes, GPU rail switching, firmware changes, and raw MSR access are
not part of this first profile.

> **Measured scope.** Resolved from the pinned source, Lab differs from Daily
> by exactly two symbols (`CONFIG_HZ_250=y`, `CONFIG_HZ=250`). It is a tick-rate
> experiment, not a hardware-lab codebase, and it must not be described as one.
>
> **What HZ=250 can show.** Preemption granularity under load: with
> `PREEMPT_LAZY` the tick is the preemption point, so a lower HZ should cost
> up to ~4 ms of additional wakeup-to-run delay on a saturated two-core
> machine. That is a measurable *latency* hypothesis.
>
> **What it cannot show.** Idle power. `NO_HZ_IDLE` already stops the periodic
> tick in idle, so the tick rate does not change idle residency or idle watts.
> Do not schedule power experiments on this profile; the free alternative is a
> `scaling_governor` comparison (`schedutil` / `ondemand` / `conservative` /
> `powersave`) on an unchanged Daily kernel, which needs no rebuild at all.

## Boot targets

Keep these entries available before testing:

| Order | Entry | ABI / identity | Purpose |
|---|---|---|---|
| Recovery | `linux-lts` | distro ABI | Known-good recovery and comparison baseline |
| Existing | Legacy experimental | `linux-mbp51-extreme` | Previously booted custom kernel evidence |
| Tier 1 | Daily | `7.3.0-mbp51-daily-g21a7f44f-v1-c2-c2` | Upstream EEVDF, 1000 Hz reference |
| Tier 2 | BORE | `7.3.0-mbp51-bore-g21a7f44f-bore7.0.0-r1-c2-c2` | BORE scheduler, 1000 Hz, default-off runtime mode |
| Tier 3 | Extreme Lab | `7.3.0-mbp51-lab-g21a7f44f-lab-hz250-r1-c2-c2` | Feature-preserving 250 Hz experiment |

The minimum experimental comparison is **Daily + BORE + Lab**, with LTS kept
as recovery. Preserving the existing legacy entry gives an additional known
physical custom-kernel reference.

## Installation gate

For each artifact directory, verify hashes and provenance, then run the
read-only plan before any installation:

```bash
MBP51_TIER=daily bash install/activate-daily-kernel.sh --plan dist/daily
MBP51_TIER=bore bash install/activate-bore-kernel.sh --plan dist/bore
MBP51_TIER=lab bash install/activate-lab-kernel.sh --plan dist/lab
```

For the first physical qualification of a tier, add `--no-wifi` to `--install`
and prove the kernel over Ethernet. Install the module afterwards with
`--wifi-only`; the boot entry is created before the vendor module either way.

The installer must leave `linux-lts`, its initramfs, the explicit LTS
`GRUB_DEFAULT`, and the legacy `/boot/mbp51/` files intact. Each tier uses its
own package base, module ABI, private Broadcom package, boot directory, and
GRUB IDs.

## Per-boot acceptance

Record the output of `scripts/compare-kernels.sh` tagged by `uname -r`, and run
`bash scripts/postboot-check.sh "$HOME/mbp51-audit/postboot-$(uname -r).txt"`
for a PASS/WARN/FAIL verdict on the same list. Every FAIL blocks promotion of
that entry. Then check the following before moving to the next kernel:

- reaches the graphical login and returns from a normal reboot;
- `USER_NS`, `MEMCG`, `PSI`, Btrfs ACL support, and zram configuration;
- ALSA soundcards, Realtek HDA playback/capture, and USB audio;
- BCM4322 `wl` module path and matching vermagic, Wi-Fi scan/connect/reconnect;
- ACPI battery/adapter reporting, UPower startup, SMC temperatures/fans;
- Apple input, webcam, USB, Ethernet, Bluetooth probes with bounded timeout;
- Nouveau 9400M display, optional 9600M render/offload, and gmux state;
- suspend/resume and shutdown; do not change GPU rails during the first pass.

Use the LTS entry immediately if a tier fails to boot or loses a required
feature. Do not change more than one experimental variable between Lab
revisions.

## Scheduler comparison

Keep the first comparison fixed at the same governor, GPU state, power profile,
workload, and thermal settling:

1. Daily EEVDF, HZ=1000.
2. BORE with `kernel.sched_bore=0`.
3. BORE with `kernel.sched_bore=1`.
4. Extreme Lab, HZ=250.

Measure latency p50/p95/p99, throughput, context switches, memory PSI, C-state
residency, temperatures, fan behavior, and power. A boot or compile pass is
not evidence of a performance or battery improvement.
