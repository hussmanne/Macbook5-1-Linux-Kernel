# Install runbook — `c2` kernels on the MacBookPro5,1

Operator checklist for taking a CI-built kernel from GitHub to a verified boot.
Follow it in order. Phases 1–2 change nothing; Phase 3 is the first mutation.

Related: [installation/recovery](INSTALL.md),
[Kconfig profile](KCONFIG-PROFILE.md),
[three-tier contract](THREE-TIER-MULTIBOOT.md),
[2026-10-29 review](REVIEW-2026-10-29.md).

Status: **no tier has ever been booted on the physical machine.** This runbook
exists to change that safely, one tier at a time, starting with Daily.

---

## Artifacts

Built by push to `main`; every ABI ends in the configuration revision `-c2`.

| Tier | Artifact name | ABI |
|---|---|---|
| legacy | `mbp51-kernel-and-headers` | `7.3.0-mbp51-extreme-g21a7f44f-v2-c2` |
| **Daily** | `mbp51-daily-kernel-and-headers` | `7.3.0-mbp51-daily-g21a7f44f-v1-c2` |
| BORE | `mbp51-bore-kernel-and-headers` | `7.3.0-mbp51-bore-g21a7f44f-bore7.0.0-r1-c2` |
| Lab | `mbp51-extreme-lab-kernel-and-headers` | `7.3.0-mbp51-lab-g21a7f44f-lab-hz250-r1-c2` |

Download from the newest successful run of the matching build workflow. The ABI
must end in `-c2`; anything else is a pre-`c2` artifact and `verify-artifacts.sh`
will reject it.

---

## Phase 0 — preconditions

- AC power connected.
- Working **Ethernet**. The proprietary Broadcom module is compiled on the
  machine and has never been loaded on it; do not make Wi-Fi a precondition for
  booting an experimental kernel.
- A known-good bootable USB.
- `linux-lts` still selectable in GRUB with its own initramfs.

```bash
cd ~/Macbook5-1-Linux-Kernel
git fetch origin && git log --oneline -3
sudo pacman -S --needed --noconfirm base-devel python kmod libarchive \
  dracut grub broadcom-wl-dkms
```

`broadcom-wl-dkms` supplies the vendor source that the patcher rewrites;
`libarchive` supplies `bsdtar`, which `make-local-package.sh` requires.

```bash
findmnt -no SOURCE,OPTIONS /
findmnt -T /boot -no SOURCE,OPTIONS
grep '^GRUB_DEFAULT=' /etc/default/grub
```

`GRUB_DEFAULT` must name `linux-lts` explicitly
(`gnulinux-advanced-<uuid>>gnulinux-linux-lts-advanced-<uuid>`), never `0`.
The installer refuses to run otherwise, and that is deliberate.

`/boot` may be a separate filesystem: boot paths are now resolved with
`grub-probe`/`grub-mkrelpath`, not assembled by hand, so a separate `/boot`
subvolume no longer produces a silently wrong menu entry. `/` itself must be
Btrfs, because `rootflags=subvol=` is emitted from it.

---

## Phase 1 — LTS baseline (the control)

Boot **`linux-lts`**. This is the control for every later comparison; without
it, no result is interpretable.

```bash
cd ~/Macbook5-1-Linux-Kernel
uname -r                     # must NOT contain -c2
bash scripts/compare-kernels.sh
bash scripts/postboot-check.sh "$HOME/mbp51-audit/postboot-lts.txt"
```

Record explicitly:

| Question | Why it decides something |
|---|---|
| Any `BAT*` in `/sys/class/power_supply`? | If LTS has none either, the missing battery was never a kernel bug — it is firmware or a dead cell. Answers a months-old open question. |
| Does `power_now` report a number? | Without it there is no watt signal and no tier can be called better. |
| Any thermal zones? | Tells you whether the benchmark harness was recording zeros. |
| How many ALSA cards? | The reference for the audio regression check. |
| Does `wl` work here? | Proves card, regulatory domain and AP before blaming the custom kernel. |

Run the pair twice; the first pass after boot is noisy. Record one idle wattage
on battery at fixed brightness with `sudo powertop` — the only honest
denominator you will get without an external meter.

---

## Phase 2 — fetch, verify, plan

```bash
cd ~/Macbook5-1-Linux-Kernel
mkdir -p dist/daily
# unzip mbp51-daily-kernel-and-headers from the newest Daily run into dist/daily
bash scripts/verify-artifacts.sh dist/daily
```

Expect the final line:

```
Verified portable package artifacts for 7.3.0-mbp51-daily-g21a7f44f-v1-c2
```

Then the read-only plan:

```bash
bash install/activate-daily-kernel.sh --plan dist/daily
```

Expect, in order: two `OK` checksum lines, the verified-ABI line, `daily ABI:`,
`Package:`, `Headers:`, `Stock linux-lts, legacy kernel, and other custom tiers
remain untouched.`, then `Read-only package verification succeeded; no
installation attempted.`

---

## Phase 3 — install

**Recommended first qualification: install without the proprietary module.**

```bash
bash install/activate-daily-kernel.sh --install dist/daily --no-wifi
```

The installer creates the boot entry *before* the Wi-Fi step either way; the
flag exists so that the most fragile component in the stack cannot decide
whether a kernel is testable. Wi-Fi is added afterwards with no second package
install and no GRUB edit:

```bash
bash install/activate-daily-kernel.sh --wifi-only dist/daily
```

To do both in one pass (only if you are confident the Broadcom build works):

```bash
bash install/activate-daily-kernel.sh --install dist/daily
```

Ordering inside `--install`, each step a barrier:

1. Re-verify artifact, DMI, Btrfs/EFI layout, LTS presence, explicit LTS default
2. `pacman -U` kernel + headers → `/usr/lib/modules/<rel>/`
3. Copy `vmlinuz` → `/boot/mbp51/daily/vmlinuz`
4. Host-only `initramfs.img` + generic `initramfs-fallback.img`
5. Resolve paths with `grub-probe`/`grub-mkrelpath`, print them
6. Write `/etc/grub.d/42_mbp51-daily`, `grub-mkconfig`, `grub-script-check`,
   confirm the title reached `grub.cfg`, re-check LTS default
7. **Then** build/install/verify the private `wl.ko` (skipped by `--no-wifi`)

Expect `Boot paths: kernel=... fs=btrfs uuid=... subvol=...` at step 5 and
`BOOTABLE: ... is in the menu; linux-lts is still the default.` after step 6.

If step 7 fails, the kernel is already bootable and LTS is still the default;
fix Broadcom and re-run `--wifi-only`. `--install` is idempotent.

Verify before rebooting:

```bash
R=7.3.0-mbp51-daily-g21a7f44f-v1-c2
ls -l /boot/mbp51/daily/
modinfo -k "$R" -n wl; modinfo -k "$R" -F vermagic wl   # only if wifi installed
sudo grep -c "MacBookPro5,1 Daily" /boot/grub/grub.cfg  # expect 2
grep '^GRUB_DEFAULT=' /etc/default/grub                 # still linux-lts
```

---

## Phase 4 — first boot

Select **"MacBookPro5,1 Daily (upstream EEVDF)"** at GRUB.

**Test the console first** — it is the largest `c2` change:

```
Ctrl-Alt-F2      # expect a text login on a framebuffer console
Ctrl-Alt-F1      # back to X
```

If X fails later, this is your only debug channel; confirm it now, not when you
need it.

```bash
uname -r    # 7.3.0-mbp51-daily-g21a7f44f-v1-c2
cd ~/Macbook5-1-Linux-Kernel
bash scripts/postboot-check.sh "$HOME/mbp51-audit/postboot-daily.txt" --no-wifi
bash scripts/compare-kernels.sh
```

Drop `--no-wifi` if the module was installed. The run ends with either
`RESULT: ACCEPTED` (WARN tolerated) or `RESULT: NOT ACCEPTED` (any FAIL).

Expected WARNs, and not defects: `battery`/`power_now` when LTS also has no
`BAT*`, `applesmc` when SMC is not bound, `journal` without cached sudo.

Manual checks, in this order — stop at the first hard failure:

1. Display 1440×900, no flicker at low brightness
2. Trackpad and keyboard, including hotkeys
3. `bash scripts/gpu-report.sh` — both Nouveau renderers, `xrandr --listproviders`
4. Audio through speakers, then headphones
5. Ethernet; Wi-Fi scan/associate only if `wl` was installed
6. `timeout -k 2 5 bluetoothctl list` (bounded — this hung in v1)
7. Shutdown completes
8. **Last:** `systemctl suspend`, manual resume, lid close/open, Wi-Fi reconnect

---

## Phase 5 — decide

```bash
bash scripts/benchmark/compare.sh <before-dir> <after-dir>
diff ~/mbp51-audit/postboot-lts.txt ~/mbp51-audit/postboot-daily.txt
```

| Verdict | Condition |
|---|---|
| **KEEP** | No `FAIL`; every Phase 4 step passes; every difference from LTS explained |
| **REVERT** | Any `FAIL` on console, DRM, audio, input, storage, or suspend fails to resume |
| **NEEDS EVIDENCE** | Boots and works, but no measurement yet separates it from LTS |

Promote Daily only on KEEP. **BORE and Lab are not worth booting until Daily is
KEEP** — each differs from Daily by exactly one configuration symbol, so a
Daily failure predicts theirs.

---

## Rollback

`linux-lts` remains the GRUB default throughout, so a reboot always recovers.

```bash
# from linux-lts
sudo pacman -Rns linux-mbp51-daily linux-mbp51-daily-headers mbp51-broadcom-wl-daily
sudo rm -f /etc/grub.d/42_mbp51-daily
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo rm -rf /boot/mbp51/daily
```

Never remove `linux-lts`, its initramfs, `/boot/mbp51/vmlinuz`, or
`/boot/mbp51/initramfs.img` (the legacy v1 entry that has physical boot
evidence).

---

## Failure → action

| Symptom | Meaning | Action |
|---|---|---|
| `Set an explicit linux-lts GRUB_DEFAULT` | guard working | set it in `/etc/default/grub`; do not force past |
| `GRUB could not resolve the boot paths` | `grub-probe` cannot map the file | check `/boot` is mounted and `grub-mkdevicemap` state; do not hand-edit an entry |
| `Cannot identify the Btrfs subvolume of /` | root not a subvolume mount | out of scope for this script; needs manual GRUB work |
| `Wrong wl module` / wrong vermagic | a stock DKMS `wl.ko` shadows the private one | `dkms status`; remove only the conflicting DKMS build, never stock's driver |
| Hostonly dracut fails | old dracut vs new kernel | packages installed, no entry created; boot LTS via the generic path |
| Black screen at boot | Nouveau modeset | `Ctrl-Alt-F2`, then `nomodeset` from the GRUB editor |
| Suspend never returns | Nouveau/gmux resume, the classic failure here | hold power, boot LTS |
| Wi-Fi dead, boot otherwise fine | `wl` not bound | boot LTS, keep Ethernet, re-run `--wifi-only` |

---

## What this runbook deliberately does not cover

GPU rail switching, `powertop --auto-tune` deployment, Penryn undervolting and
SATA ALPM. Each is a separate experiment that needs a KEEP baseline first; see
[the review](REVIEW-2026-10-29.md) sections 3 and 7.
