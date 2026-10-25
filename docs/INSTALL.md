# Installation and recovery — manual, experimental

**Do not wipe an existing OS or install this kernel as your sole kernel.**

Use an installed Arch/EndeavourOS system with a confirmed working stock
kernel, accessible GRUB rescue entry, MagSafe connected, wired network
fallback, and bootable recovery USB. Verify important data backups and Apple
recovery media independently; Catalina's APFS Recovery volume is erased with
its APFS container.

Download the kernel and headers packages from a completed *manual* GitHub
Actions build. Verify sha256 checksums and kernelrelease.txt. Inspect the
contents with pacman -Qip and pacman -Qlp before installing. Install both
packages together via pacman -U, never replace the stock Arch kernel.

Broadcom BCM4322 uses proprietary broadcom-wl-dkms: the external module must
be installed and successfully built for the custom kernel, with exactly
matching headers. Check dkms status and explicitly build using
dkms autoinstall -k KERNELRELEASE (replace with the value in the artifact).
A successful kernel compile does not guarantee that wl works against an
unreleased Linux development tree. Wired MCP79 Ethernet is the fallback.

Do not guess the machine's EFI mount, /boot mount, or dracut versus mkinitcpio
choice. On the installed machine verify mount points with findmnt, check the
current stock boot entry and kernel image, copy the new module-directory
vmlinuz into the *correct* boot location, generate the matching initramfs
using the installed generator, and regenerate GRUB configuration. Inspect
GRUB entries; stock kernel must remain bootable. Never automate this step
blindly in GitHub Actions.

First hardware-qualification boot: confirm uname -r, Nouveau GL on both
9400M/9600M, gmux/vga_switcheroo, Apple HID/trackpad/brightness, SMC sensor
temperatures, forcedeth, Broadcom wl connection/reconnect, audio, camera,
disk errors, shutdown and ACPI S3 manual and lid suspend/wake. Avoid prolonged
stress if battery health is uncertain.

Only after these checks, install powertop, systemd-zram-generator and copy
runtime templates to the corresponding system paths (unit files to
/etc/systemd/system, zram-generator to /etc/systemd, sysctl to
/etc/sysctl.d, wake hook to /usr/lib/systemd/system-sleep; make it executable).
Enable mbp51-powertop.service, restart the system and check whether global
auto-tune affects USB, wireless, disk or suspend. Narrow exceptions only for
demonstrated regressions; do not silently remove global auto-tune.

The kernel is compiled with CONFIG_CPU_MITIGATIONS=n. Boot parameters cannot
restore microarchitectural attack mitigations in this binary. Reboot the stock
Arch kernel if protections are required.

Recovery: select stock Arch/LTS in GRUB. If the custom kernel broke graphics
or networking, use USB/Ethernet or the rescue image; boot stock and remove
the custom kernel/header packages with pacman. Btrfs snapshots are useful,
but they are not replacements for backups or an independent bootloader.
