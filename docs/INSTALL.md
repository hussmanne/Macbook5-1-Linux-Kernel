# MacBookPro5,1 — recoverable installation and first-boot qualification

**Experimental kernel; no successful physical MacBook boot has been established.**
Never erase a working OS or replace the stock boot entry. These instructions are
for **an already installed Arch-derived Linux OS**. Do not apply Arch pacman
packages on MX Linux, macOS, or a different distribution. Use a recovery USB,
AC power and a working wired/USB network path.

## 1. Read-only preparation on the MacBook

Run from an ordinary user shell in this repository:

```bash
bash scripts/hardware-report.sh | tee "$HOME/mbp51-before.txt"
uname -r
findmnt -o SOURCE,TARGET,FSTYPE / /boot /efi 2>/dev/null || true
ls -l /boot/  # first determine whether this is the real mounted boot partition
pacman -Q | grep -E '^(linux|linux-lts|grub|systemd|mkinitcpio|dracut|broadcom)'
```

Check that a **known-good stock kernel** remains separately bootable and has
its own initramfs and modules, that backups exist, and that the bootloader can
select it (GRUB or systemd-boot). Do not proceed if boot partition location,
bootloader, initramfs system, or root filesystem is uncertain.

## 2. Verify the downloaded kernel/header pair

Download the **newest successful** `mbp51-kernel-and-headers` artifact from
GitHub Actions for the exact revision of this repository. Unzip it into
`dist/` and from the repository root run:

```bash
bash scripts/verify-artifacts.sh dist
K=$(cat dist/kernelrelease.txt)
printf 'Target ABI: %s\n' "$K"
```

The expected development-source-specific suffix is
`-mbp51-extreme-g21a7f44`. The source Makefile may still say 7.3.0:
this **does not** indicate a released 7.4 kernel. Never use a package/headers
pair for an older `-mbp51-extreme` release.

## 3. Install without booting the new kernel

While booted into the working stock kernel, and **only after boot layout and
recovery are verified**, install the two matching packages:

```bash
sudo pacman -U dist/linux-mbp51-extreme-[0-9]*-x86_64.pkg.tar.zst \
  dist/linux-mbp51-extreme-headers-[0-9]*-x86_64.pkg.tar.zst
```

An existing `broadcom-wl-dkms` post-transaction hook may attempt and fail to
build `wl` for these bleeding-edge headers. Do not confuse that with failure
to install the kernel. We use a separately patched module next; retain stock
kernel networking.

## 4. Build a LOCAL, pacman-managed Broadcom module

The official Arch `broadcom-wl-dkms` source does not itself contain every
change needed by this upstream development snapshot. The following command
copies it, applies source-locked fixes, builds `wl.ko` and produces a normal
Arch package. It does **not** install or load anything by itself.

```bash
sudo pacman -S --needed base-devel python kmod broadcom-wl-dkms
bash compat/broadcom/make-local-package.sh "$K"
```

Verify the resulting `.work/broadcom/$K/package/mbp51-broadcom-wl-*.pkg.tar.zst`
package and its `module-package.sha256`, then install:

```bash
(cd ".work/broadcom/$K/package" && sha256sum -c module-package.sha256)
sudo pacman -U ".work/broadcom/$K/package/"mbp51-broadcom-wl-*.pkg.tar.zst
modinfo -k "$K" -n wl
modinfo -k "$K" -F vermagic wl
```

The module path should resolve to
`/usr/lib/modules/$K/updates/mbp51/wl.ko`, with matching vermagic. If
another DKMS wl.ko shadows it, investigate module resolution **before boot**
and do not uninstall the stock-kernel driver merely to silence the conflict.

The local package is named `mbp51-broadcom-wl`, is pacman-managed and is
bound to exactly one kernel release. **It is not DKMS-managed**; rebuild it
when the custom kernel source or ABI changes. This avoids redistributing the
vendor's proprietary binary via GitHub.

## 5. Prepare the real boot entry — inspection required

The upstream kernel package places its vmlinuz under
`/usr/lib/modules/$K/vmlinuz` but cannot know your live boot layout.
Determine actual mountpoints with `findmnt`, identify your initramfs generator
(`mkinitcpio` or `dracut`) and the current bootloader (`grub` or
`systemd-boot`). Only then make a **separate** custom-kernel image/initramfs
and boot entry referring to the correct root volume and filesystem.
**Do not blindly run generic `cp /boot/...` or overwrite an existing entry.**
Keep the original kernel image, stock initramfs and working bootloader entry.

## 6. One manual qualification boot

Boot the new entry with AC connected. First verify `uname -r` matches
`$K`. While network fallback remains available, check in this order:
display/backlight and both Nouveau renderers, Apple keyboard/trackpad and SMC
temperatures, SATA storage/errors, forcedeth Ethernet, `wl` radio and WPA2
scanning/association, audio, webcam, Bluetooth, and system shutdown.
Capture:
```bash
bash scripts/hardware-report.sh | tee "$HOME/mbp51-custom-before-power.txt"
```

Manually test ACPI S3 suspend/resume and lid-close **only after confirming
a recovery boot is available**, and repeat the report after resuming.
Test Wi-Fi reconnect and inspect `journalctl -k -b`. Do not automatically
disable the discrete NVIDIA GPU or force PCIe ASPM.

Only after the baseline survives these checks, install `powertop` and
`systemd-zram-generator`, deploy the runtime templates, and enable the
requested global PowerTOP tuning. The repository preserves that preference
but does not force it during the first, reversible boot. Compare idle power,
CPU temperatures, input latency and sleep-drain against the stock kernel.

## Recovery and security

Select the known-good stock entry if any component breaks. Boot stock, then
remove the locally packaged module and the custom packages if appropriate:
`sudo pacman -R mbp51-broadcom-wl linux-mbp51-extreme-headers linux-mbp51-extreme`.
Never remove the stock kernel/headers. Kernel `CONFIG_CPU_MITIGATIONS=n`
is an intentional reduction in speculative-execution protections and cannot
be reversed with a boot parameter on this custom binary.
