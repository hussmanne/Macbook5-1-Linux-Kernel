# Power and performance — what is actually left (2026-10-29)

Question asked: *would any 7.4 commits since our pin benefit this machine, and
what else can be cut or tweaked for battery life and everyday performance?*

Same labels as [REVIEW-2026-10-29.md](REVIEW-2026-10-29.md):

- **[measured]** — executed during this session against upstream or this repo.
- **[inferred]** — read out of the pinned source or this repo's scripts.
- **[estimate]** — judgement, with the reasoning shown. Not a measurement.

Short answer: **no 7.4 commit since the pin helps this machine, and cutting
more out of the kernel will not save battery. The two levers that actually
matter are the discrete GPU and the panel brightness, and neither is a build
option.** Details, and what to do instead, below.

---

## 1. The 7.4 question

### 1.1 What our pin actually is

`source.lock` calls the pin a "7.4 development merge-window snapshot" and
records `KERNEL_VERSION=7.3.0`, because the upstream `Makefile` at
`21a7f44f` still says 7.3.0. Both halves of that are true and they point in
the same direction: **[inferred] the pin sits about four days into the 7.4
merge window.** It is 7.3.0 plus the first few 7.4 subsystem merges — not a
release, and not really "7.4" either.

That has a consequence worth stating plainly: our `uname -r` says `7.3.0`
while the tree contains partially-merged 7.4 subsystem code. This is a
hygiene problem, not a performance problem, and it is why the version string
should be read as "a specific commit", never as "7.3.0".

### 1.2 What has landed since

**[measured]** At the time of writing, `master` is **296 first-parent commits**
ahead of the pin, **81 of them subsystem merges**.

**[measured]** Rather than trusting `?path=` commit filters — which attribute
merge commits inconsistently — I compared directory tree SHAs at the pin and at
`master`. A directory's tree SHA covers its entire subtree, so "identical tree
SHA" is proof that nothing inside changed:

| Path | Pin vs now | Why it matters here |
|---|---|---|
| `drivers/gpu/drm/nouveau` | **SAME** (81 entries) | both GPUs, the desktop compositor |
| `drivers/cpufreq` | **SAME** (93) | `acpi-cpufreq`, `schedutil` |
| `drivers/cpuidle` | **SAME** (40) | the idle governors that decide C-states |
| `sound/hda` | **SAME** (6) | the whole HDA stack, controller and codecs |
| `drivers/platform/x86` | CHANGED (64) | but not `apple-gmux.c` — see below |
| `drivers/ata` | CHANGED (42) | `ahci.c`, `libahci.c`, `libata-core.c` |
| `drivers/acpi` | CHANGED (6) | `Kconfig`, `riscv/`, `video_detect.c` |
| `drivers/video/backlight` | CHANGED (10) | `ili9320`, `ktd253`, `lm3533`, `lm3630a`, `qcom-wled` |
| `kernel/sched` | CHANGED (8) | entirely `sched_ext` |
| `mm`, `fs/btrfs` | CHANGED | allocator, page cache, our root filesystem |

Every Apple-specific file is byte-identical between the pin and `master`:
`apple-gmux.c`, `applesmc.c`, `apple_bl.c`, `apple_mfi.c`, `acpi/battery.c`.

**[measured]** The only "apple" string in those 296 commits is a `cdc_ncm` USB
Ethernet device ID for an Apple Silicon MacBook Air — a 2020 machine, not ours.

### 1.3 The three changes that could have mattered

I read all three rather than trusting the diffstat:

- **[measured]** `libahci.c` (+42/−2) fixes two things: `ahci_error_handler()`
  now re-enables FBS after a failed port-multiplier softreset, and
  `ahci_host_activate_multi_irqs()` frees IRQs on its error path. Both are
  **port-multiplier and multi-IRQ paths**. A MacBookPro5,1 has one AHCI
  controller, one port, no PMP, one IRQ. Not applicable.
- **[measured]** `libata-core.c` (+90/−12) reworks `ata_force_xfermask()` /
  `libata.force=` parsing. We pass no `libata.force=` argument.
- **[measured]** `acpi/video_detect.c` (+0/−8) only deletes an
  `#ifdef CONFIG_X86` around `nvidia_wmi_ec_supported()`, so the file compiles
  on non-x86. Zero behaviour change on x86.

**Conclusion: zero commits since the pin benefit this machine.** Every one of
the 81 merges is either hardware we do not have, code paths we do not take, or
`-rc1` regression fixes to subsystems that were already merged before our pin.

### 1.4 So should we move the pin?

Not now, and not for this reason. When `v7.4-rc1` is tagged — roughly two weeks
after the window opened — moving the pin there is worth doing for **coherence**
(a tagged tree, a truthful version string, and every subsystem's `-rc1` fix
round included), not because anything in it makes the machine faster or cooler.

Moving mid-window would mean rebasing the BORE patch onto churn for no
functional gain, and re-running four builds against a moving target. If the
move happens, it should be one deliberate hop to the tag, with the BORE patch
rebased once and `MBP51_CONFIG_REV` bumped to `c3`.

---

## 2. Where the watts actually are

**[estimate]** Idle power budget for a 15-inch 2009 unibody MacBook Pro, in
descending order of what each item is worth. The percentages are my reading of
what this class of machine does; they are the reason the ordering matters, not
a claim of precision.

| # | Lever | Worth | Mechanism | State in this repo |
|---|---|---|---|---|
| 1 | Discrete GPU suspended | **5–8 W** (~50%) | `apple-gmux` + `vgaswitcheroo` | capability built, procedure undocumented |
| 2 | Panel brightness | **1–3 W** | backlight driver | works, user-controlled |
| 3 | Package C-states | 0.5–2 W | `acpi_idle` via `ACPI_PROCESSOR` | already on |
| 4 | SATA link power management | 0.3–1 W | `SATA_MOBILE_LPM_POLICY` | **already at default 3** |
| 5 | Wi-Fi power save | 0.3–0.7 W | `cfg80211` PS | default `y`, `wl` behaviour unverified |
| 6 | HDA codec suspend | 0.2–0.5 W | `snd_hda_intel.power_save` | **default 0** — only powertop turns it on |
| 7 | PCIe ASPM | 0.2–1 W | link states | policy unverified, risky on MCP79 |
| 8 | Background wakeups | 0.2–1 W | `powertop --auto-tune` | already scheduled |
| 9 | Kernel config trimming | **~0 W** | size only | see §5 |

Read rows 1 and 2 again: **most of the achievable saving is not in the
kernel.** Rows 1–2 are worth more than rows 3–9 combined, and no amount of
`CONFIG_` work touches them.

---

## 3. What is already correct (verified, not assumed)

This is the part that says "stop looking here":

- **[measured]** `SATA_MOBILE_LPM_POLICY` has `range 0 5` and **`default 3`**
  (`drivers/ata/Kconfig` at the pin), i.e. `med_power_with_dipm`, the value
  every laptop distro ships. Nothing to change.
- **[measured]** `CFG80211_DEFAULT_PS` is **`default y`** — Wi-Fi power save is
  on by default.
- **[measured]** `USB_AUTOSUSPEND_DELAY` is **`default 2`** seconds.
- **[measured]** `SND_HDA_POWER_SAVE_DEFAULT` is **`default 0`**, documented as
  *"0 means to disable the power-save mode"*. This is the one default that is
  working against us — see §4.2.
- **[measured]** `WQ_POWER_EFFICIENT_DEFAULT` has no default (Kconfig says "if
  in doubt, say N"), so it is **off**.
- **[inferred]** `scripts/configure.sh` already sets
  `CC_OPTIMIZE_FOR_PERFORMANCE`, `NO_HZ_IDLE`, `HIGH_RES_TIMERS`,
  `CPU_FREQ_DEFAULT_GOV_SCHEDUTIL`, `SCHED_AUTOGROUP`, `LRU_GEN`, and builds
  **both** `CPU_IDLE_GOV_MENU` and `CPU_IDLE_GOV_TEO` so the idle governor is a
  runtime choice rather than a rebuild.
- **[measured]** The audio codec is right. `sound/hda/codecs/realtek/alc882.c`
  line 643 contains `SND_PCI_QUIRK(0x106b, 0x4000, "MacbookPro 5,1",
  ALC889_FIXUP_IMAC91_VREF)` — upstream has an explicit quirk for this exact
  machine, and our `SND_HDA_CODEC_REALTEK=m` + `SND_HDA_GENERIC=m` is what
  makes it reachable. The Cirrus fixup table (`cs420x.c`) lists 5,3 / 5,5 /
  7,1 / 8,1 / 10,1 and deliberately **not** 5,1, which confirms 5,1 is a
  Realtek machine. No change needed.

---

## 4. What is genuinely winnable

### 4.1 The discrete GPU — the whole ballgame

**[measured]** Upstream `drivers/platform/x86/apple-gmux.c` names this machine:

> "The earliest generation MBP5 2008/09 uses a `TI LP8543` backlight driver."
> "On dual GPU MacBook Pros … either GPU may be suspended to conserve energy."
> "The external DP port is only fully switchable on the first two unibody
> MacBook Pro generations, MBP5 2008/09 and MBP6 2010."

So the gmux exists on an MBP5,1, it controls the panel backlight independently
of either GPU, and the second GPU can be suspended. Our config already builds
the three pieces needed: `APPLE_GMUX`, `VGA_SWITCHEROO`, `DRM_NOUVEAU` (module).

This is deliberately **not automated**, per the repository rule against
automatic GPU rail-off. A manual procedure, run at a console:

```sh
# 1. Confirm the machine exposes two switchable GPUs.
sudo cat /sys/kernel/debug/vgaswitcheroo/switch
#   expected: two lines, IGD and DIG, both bound to nouveau

# 2. Measure the baseline while the discrete GPU is ON.
sudo ./scripts/power-idle.sh --label gpu-on --seconds 120 --out /var/tmp/power.csv

# 3. Power the discrete GPU down (the saving), keep the integrated one driving.
echo OFF | sudo tee /sys/kernel/debug/vgaswitcheroo/switch

# 4. Measure again; the delta is the answer, in watts.
sudo ./scripts/power-idle.sh --label gpu-off --seconds 120 --out /var/tmp/power.csv

# 5. Undo, if anything looks wrong (black screen, no backlight):
echo ON | sudo tee /sys/kernel/debug/vgaswitcheroo/switch
```

Two caveats that decide whether this works at all, and both are one command to
check on the machine: whether the firmware booted with both GPUs visible, and
whether `vgaswitcheroo` lists two clients on **this** firmware revision. If it
lists one, the lever does not exist on this machine as configured, and the
battery expectation has to be set lower. Do not assume it from the source.

### 4.2 HDA codec power save — a verified default working against us

**[measured]** `SND_HDA_POWER_SAVE_DEFAULT` is 0, so the codec never suspends
unless something sets `power_save` afterwards. `powertop --auto-tune` does set
it, and `runtime/system-sleep/50-mbp51-powertop` re-applies on resume — but
between boot and the first powertop run, and on any boot where that unit fails,
the codec stays powered. Making it the default costs nothing:

```sh
# /etc/modprobe.d/mbp51-audio-power.conf
options snd_hda_intel power_save=1
```

**[estimate]** 0.2–0.5 W, and it may add a faint pop on the first sound after
idle; if it does, `power_save=2` is the usual compromise.

### 4.3 Workqueues — small, and free at boot

**[measured]** `wq_power_efficient` is compiled in as a **read-only** module
parameter (`module_param_named(power_efficient, wq_power_efficient, bool, 0444)`),
so it can only be changed at boot. Add `workqueue.power_efficient=1` to the
kernel command line. **[estimate]** 0.1–0.3 W, with a small throughput cost.

### 4.4 PCIe ASPM — do not touch until measured

**[inferred]** On MCP79, ASPM has historically been a source of link-training
failures and dropped Wi-Fi. Read the current policy before changing anything:

```sh
cat /sys/module/pcie_aspm/parameters/policy
```

If it says `default` and `powertop` shows PCIe links in `L0` with no `L1`, test
`pcie_aspm.policy=powersupersave` as a boot parameter, one boot, with the
script measuring. **[estimate]** 0.2–1 W when it works; a dead Wi-Fi card when
it does not.

### 4.5 Filesystem and swap — real, and free

Not kernel configuration, but the cheapest wins available:

- **[inferred]** `noatime` on `/` (and `/home`). Default is `relatime`; `noatime`
  removes the metadata write on every read.
- **[inferred]** `commit=60` or `commit=120` on Btrfs — fewer periodic
  writeback wakeups, at the cost of a larger window of lost writes on power
  loss. A laptop that is suspended, not powered off, rarely cares.
- **[inferred]** `compress=zstd:1` (not `zstd:3`) on Btrfs. On a 2.4 GHz Core 2,
  `zstd:3` spends real CPU time to save I/O you were not waiting on.
- **[inferred]** With zram-generator, the standard tuning is
  `vm.swappiness=100`, `vm.page-cluster=0`, `vm.watermark_boost_factor=0`,
  `vm.watermark_scale_factor=125`. It keeps more in compressed RAM and touches
  the disk less.

### 4.6 Wi-Fi power save under `wl`

**[inferred]** `cfg80211` defaults to PS on, but the Broadcom `wl` blob is not a
mac80211 driver and does not always honour it. One command decides:

```sh
iw dev wlan0 get power_save          # "on" / "off"
sudo iw dev wlan0 set power_save on
iw dev wlan0 get power_save
```

Then confirm it survives a resume. **[estimate]** 0.3–0.7 W when it holds.

---

## 5. Can we cut more? Yes — but it will not help the battery

**[measured]** `c1` → `c2` removed 50 built-in symbols (`=y` 1622 → 1572, 90
symbols off) and the shipped artifact went from **30.7 MiB to 30.8 MiB**, i.e.
**+0.3 %**. Stripping buys a smaller surface to explain and a slightly shorter
boot; it does not buy watts, because an unused driver that never loads costs
nothing once the machine is idle.

Remaining candidates, with what each actually buys:

| Symbol | What cutting it buys | Risk |
|---|---|---|
| `SND_SEQUENCER`, `SND_HRTIMER`, `SND_SEQ_DUMMY` | tens of KiB | MIDI/sequencer apps stop working |
| `SERIAL_8250*`, `NETCONSOLE` | KiB | lose the netconsole log channel |
| `ATA_PIIX`, `PATA_AMD`, `PATA_OLDPIIX`, `PATA_SCH` | KiB | lose an odd external optical drive path |
| `CIFS`, `QUOTA`, `SCSI_SPI_ATTRS`, `USB_PRINTER`, `USB_MON` | KiB | nothing today |
| `X86_INTEL_PSTATE` | a driver that **cannot bind** on Penryn; removes a confusing dmesg line | none |
| `EXFAT_FS` | KiB | no exFAT volumes |
| `HARDLOCKUP_DETECTOR` | one periodic NMI per CPU | lose a crash diagnostic |
| `MEDIA_*`, `VIDEO_DEV`, `USB_VIDEO_CLASS` | ~1 MB | the iSight camera stops working |
| `BT`, `BT_HCIBTUSB` | ~200 KiB + a radio that stays powered | no Bluetooth |
| `FIREWIRE_OHCI` | KiB, and possibly 0.3 W if the PHY stays in D0 | no FireWire |

The last two are the only entries in that table that might be worth real watts,
and both are **[estimate]** until measured with the script: a loaded FireWire
PHY and a loaded Bluetooth radio can each hold a device out of its lowest power
state. Test by unbinding, not by rebuilding:

```sh
sudo sh -c 'echo 0000:0b:00.0 > /sys/bus/pci/drivers/firewire_ohci/unbind'  # adjust address
```

One genuine correctness gap found while checking this: **`CONFIG_SWAP` is
load-bearing and unasserted.** Every document that says "zram-generator owns
LZ4 swap" depends on it, `scripts/configure.sh` never sets it, and
`scripts/audit-config.sh` never checks it. It currently arrives as a Kconfig
default (`default y`), so today it is fine — but a silent `n` would make zram
useless without failing a single gate. That belongs in the audit regardless of
battery.

---

## 6. For everyday performance

**[estimate]** On a 2009 Core 2 Duo, the three largest performance factors are
RAM (8 GB), storage (SSD over the original 5400 rpm disk) and the GPU — in that
order. No config symbol in this repository approaches an SSD upgrade.

What the kernel already does right, and should not be second-guessed:

- **[inferred]** `CONFIG_CPU_MITIGATIONS=n` is the single largest syscall-path
  win on Penryn and is already the user's documented, disclosed choice.
- `CC_OPTIMIZE_FOR_PERFORMANCE`, `-mtune=core2` without `-march=native`,
  `schedutil`, `LRU_GEN`, `SCHED_AUTOGROUP`.

What can be A/B'd without a rebuild:

- **Preemption**: `PREEMPT_DYNAMIC` is on, so `preempt=voluntary` (default),
  `preempt=full`, or `preempt=none` are boot-time choices. `none` favours
  throughput and battery, `full` favours latency.
- **Idle governor**: `cpuidle.governor=menu|teo` — both are built in. TEO is the
  default here; `menu` is the conservative choice if C-state residency looks
  low.
- **I/O scheduler**: `MQ_IOSCHED_DEADLINE` and `KYBER` are both built and BFQ is
  off, which is right for two cores. On an SSD, `none` is usually fastest;
  check `cat /sys/block/sda/queue/scheduler`.
- **Tick rate**: the Daily/Legacy tiers run `HZ=500`, Lab `HZ=250`, BORE
  `HZ=1000`. With `NO_HZ_IDLE` the tick stops when idle, so the tier differences
  only affect loaded behaviour. **[estimate]** 250 is the best balance for this
  class of machine.

And the honest GPU trade-off: **the 9400M is the frugal GPU and the 9600M GT is
the fast one, and gmux is how you choose.** There is no configuration in which
you get both. The everyday desktop should run on the 9400M with the discrete
card powered down; the 9600M is for the workload that needs it.

---

## 7. A `c3` revision, if you want one

Not applied. Nothing here is worth a rebuild on its own; each is listed with
the runtime test that would justify it first.

| Symbol | Current | Change | Test it at runtime first |
|---|---|---|---|
| `WQ_POWER_EFFICIENT_DEFAULT` | n | y | `workqueue.power_efficient=1` on the cmdline |
| `SND_HDA_POWER_SAVE_DEFAULT` | 0 | 1 | `options snd_hda_intel power_save=1` |
| `X86_INTEL_PSTATE` | y (default) | n | none needed; it cannot bind |
| `HARDLOCKUP_DETECTOR` | y | n | `nmi_watchdog=0` |
| `TRANSPARENT_HUGEPAGE` | (choice) | verify `madvise` | `/sys/kernel/mm/transparent_hugepage/enabled` |
| `SWAP` | y (default) | assert in audit | none; a gate, not a change |

If measurement says these are worth less than the noise floor — which is the
likely outcome for all but the first two — the correct decision is to change
nothing and keep the artifacts you have already built and tested.

---

## 8. What to run on the machine, in order

1. Boot the Daily kernel from [INSTALL-RUNBOOK.md](INSTALL-RUNBOOK.md) Phase 4.
2. `sudo ./scripts/postboot-check.sh` — the acceptance gate.
3. `sudo ./scripts/power-idle.sh --label stock --seconds 300 --out /var/tmp/power.csv`
   — the number this whole document is about.
4. `cat /sys/kernel/debug/vgaswitcheroo/switch` — do the two GPUs exist?
5. If yes: the §4.1 procedure, measuring before and after.
6. `iw dev wlan0 get power_save`, `cat /sys/module/pcie_aspm/parameters/policy`,
   `cat /sys/devices/system/cpu/cpuidle/current_governor`.
7. Apply §4.2 and §4.3, measure again. Keep what wins, revert what does not.

---

## 9. Limits of this document

- No watt has been measured. Everything in §2 is an estimate until step 3 of
  §8 runs on the machine.
- Whether `vgaswitcheroo` exposes two GPUs on this firmware is unknown and is
  the single fact that decides how much battery life is available.
- Nouveau on a 9400M keeps the GPU clocked even when the desktop is idle; if
  the baseline idle draw is high with the discrete GPU already off, that is the
  next thing to investigate, not the kernel config.
- Nothing here is a substitute for the physical boot this project still has not
  performed.
