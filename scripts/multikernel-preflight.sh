#!/usr/bin/env bash
# Read-only preflight for a planned four-entry multi-kernel GRUB install.
# Does not install, wipe, switch GPUs or tune any power control.
set -uo pipefail
section(){ printf '\n===== %s =====\n' "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }
section "HOST"; date -Iseconds; uname -r; cat /sys/class/dmi/id/product_name 2>/dev/null || :
section "FILESYSTEM / FREE SPACE"
if have findmnt; then
  findmnt -no SOURCE,FSTYPE,OPTIONS /
  findmnt -no TARGET,FSTYPE,SOURCE /boot/efi 2>&1 || :
fi
df -h / /boot /boot/efi 2>&1 || :
section "INSTALLED KERNEL PACKAGES"
if have pacman; then
  pacman -Q linux linux-lts linux-mbp51-extreme linux-mbp51-extreme-headers \
    linux-mbp51-daily linux-mbp51-bore linux-mbp51-extreme-lab 2>&1 || :
fi
section "STOCK RECOVERY"
for f in /boot/vmlinuz-linux-lts /boot/initramfs-linux-lts.img /boot/grub/grub.cfg; do
  [[ -s "$f" ]] && echo "OK $f" || echo "MISSING or unreadable $f"
done
section "GRUB DEFAULT / CONFIG"
grep '^GRUB_DEFAULT=' /etc/default/grub 2>&1 || :
if have sudo && sudo -n true 2>/dev/null; then
  timeout -k 2 5 sudo -n grep -E "^[[:space:]]*(menuentry|submenu) " /boot/grub/grub.cfg 2>&1 | head -25 || :
else
  echo "Use sudo -v and rerun to include root-only GRUB menu details."
fi
section "EXPERIMENTAL KERNEL BOOT FILES"
find /boot/mbp51 -maxdepth 3 -type f -printf '%p %k KiB\n' 2>&1 || :
section "CONFLICT RISKS"
echo "Legacy linux-mbp51-extreme package + /boot/mbp51/vmlinuz NOT multi-tier safe."
echo "Three-tier rollout must use three distinct pacman pkgbase and boot directories."
echo "Do not run archiso-install.sh on the existing working SSD."
section "PASS: read-only inspection finished"
