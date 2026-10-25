# MacBookPro5,1 Linux kernel v2: measured hardware recovery and optimization

**State:** implementation candidate, NOT yet physically tested. Source remains the
pinned post-7.3 Linux 7.4-development snapshot. Exact kernel suffix gains `-v2`
to prevent reusing v1 DKMS/header ABI. Do not mistake successful CI for a
successful boot on the actual MacBook.

## Hardware findings, October 25, 2026

- MacBookPro5,1 / Penryn P8600 dual core 2.4GHz, 8GB RAM, working C3 and
  schedutil, P-states 1596/1862/2128/2394MHz.
- First custom boot confirmed Broadcom BCM4322 patched wl, Nouveau 9400M
  + 9600M GT, Btrfs on ADATA SSD, and LZ4 ZRAM.
- MCP79 HDA controller loads, but ALSA sees no cards: Realtek codec missing.
- UPower systemd 217/USER because USER_NS=n; MEMCG and PSI were also off.
- ACPI enumerates PNP0C0A:00 but no BAT0/BAT1 in power_supply; built-in
  battery and embedded controller support already exist. SBS module may help
  but its presence does not prove firmware will enumerate the battery.
- Apple gmux 1.7.3 and vga_switcheroo exist; internal LVDS is on 9400M,
  while unused 9600M GT was still active around 65C.
- gmux_backlight reports 0..16138, physical value ~2543. Flicker also occurs
  on the stock kernel; test PWM versus Nouveau dithering and LVDS hardware.
- Repeated Nouveau/Xorg drm_atomic_check_only WARN on this development tree.
- Bluetooth btusb endpoint enumeration failure; bluetoothctl can hang.
- Btrfs ACL disabled, with journald Operation not supported warnings.
- Generic Dracut initramfs was ~146 MiB.

## Build v2 (required)

- Enforce USER_NS, MEMCG, PSI, Btrfs POSIX ACL, ACPI_EC/BATTERY,
  SND_HDA_CODEC_REALTEK, SND_HDA_GENERIC and SND_USB_AUDIO.
- Build ACPI_SBS module as a hardware diagnostic option; retain applesmc,
  dual Nouveau GPUs, Apple gmux, Ethernet, FireWire, suspend and sensors.
- Drop CGROUP_DEBUG; upstream presently resolves AMD P-state=y and cannot
  be disabled via scripts/config (harmless on Penryn). Keep RCU, CPU idle, schedutil,
  preemption, LZ4 ZRAM, Btrfs, CPU mitigations policy, and 1000Hz default.
- CI must resolve pinned Kconfig and fail for non-matching symbols; main
  kernel build must provide exact release ABI, headers and checksums.
- Patch the EndeavourOS installer: /lib vs /usr/lib realpath matching;
  require an explicitly selected LTS default; fix sudo for GRUB verification;
  generate host-only primary plus generic fallback and two manual entries.
- Never remove official Arch linux or linux-lts packages or their boot files.

## Separate experiments after corrective boot

1. **Schedulers:** baseline is the post-7.3 7.4-development EEVDF with
   PREEMPT_LAZY. Investigate BORE 7.0.0: newest available patch targets
   7.3-rc2, and touches sched/fair.c heavily. Review/port it on separate
   branch, never silently cherry-pick onto the v2 baseline. Evaluate
   EEVDF against BORE on CPU-saturated Firefox/LXQt interactions and a
   compilation job, including p95 input latency and compile completion time.
   Keep runtime switch (when BORE is built), baseline default until verified.
   sched_ext needs BPF syscall/JIT/BTF and is a separate higher-footprint
   option, not part of the lean corrective build.
2. **GPU:** retain dual-GPU hardware, do not permanently blacklist 9600M.
   Record xrandr --listproviders, renderers, DRM nodes, vga_switcheroo state
   and user processes holding GPU devices. First determine whether PRIME
   offload works with this old Nouveau pair. Otherwise design explicit
   9400M battery / 9600M performance modes, with possible display-server
   restart and manual recovery. Only test discrete OFF/ON interactively,
   not in any boot script; PCI removal alone is not rail power-off.
3. **Power:** measure battery discharge, idle CPU C3, GPU temperatures/fans,
   SATA ALPM, USB autosuspend, HDA idle time, wireless link reliability,
   and suspend drain. Do not force pcie_aspm=force or risky min_power SATA
   policy. Keep requested powertop --auto-tune with device exceptions and
   no competing automatic TLP service.
4. **Voltage:** explore PHC-style Penryn undervolting compatibility on a
   separate experimental kernel. Stock voltage unless deliberately opted in.
   Never introduce raw MSR/clockgen PWM writes or overclock in v2.
5. **Brightness:** characterize gmux-backlight values and any low-duty
   flicker, compare with stock LTS. Software dimming and DPMS are separate
   from hardware backlight-off and have distinct power consequences.
6. **Footprint:** measure compressed vmlinux, installed modules and initramfs.
   Primary host-only Dracut with generic fallback; retain hardware you
   actually possess, including FireWire, webcam, external USB and both GPUs.

## Verification gates

A. GitHub PR lint + Kconfig; then compile on main and verify hashes.
B. No automatic deployment to the laptop. Install packages manually,
   build private matching patched wl from local Arch sources, check vermagic,
   preserve stock LTS boot, verify explicit LTS GRUB default.
C. Physical boot of v2: uname suffix -v2; Wi-Fi; ALSA codec/speakers/headphone;
   UPower daemon; BAT* power_supply (reported separately); both GPU paths;
   Btrfs ACLs, ZRAM and ordinary LXQt operation.
D. Compare Xorg DRM warnings, btusb and timed Bluetooth inventory, brightness
   stability and suspend/resume against stock LTS. Ensure shutdown works.
E. Only then run GPU power, scheduler and undervolting experiments. Record
   baseline measurements and a rollback path for each.

The existing v1 userspace state is not proof of hardware correctness.
The MacBook remains LTS-default unless the user explicitly selects v2.
