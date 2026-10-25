#!/usr/bin/env bash
# Separate experimental kernel entry; LTS always remains GRUB default.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
source "$repo/source.lock"
mode=--plan
dist="$repo/dist"
[[ $# -lt 1 ]] || mode="$1"
[[ $# -lt 2 ]] || dist="$2"
[[ "$mode" == --plan || "$mode" == --install ]] || {
  echo "Usage: $0 --plan [DIST_DIR] | --install [DIST_DIR]"; exit 2;
}
[[ "$EUID" -ne 0 ]] || { echo "Run as ordinary user, sudo handles install"; exit 2; }
bash "$repo/scripts/verify-artifacts.sh" "$dist"
release=$(cat "$dist/kernelrelease.txt")
[[ "$release" == "7.3.0$KERNEL_LOCALVERSION" ]] || {
  echo "Wrong pinned release: $release" >&2; exit 2;
}
shopt -s nullglob
kernels=("$dist"/linux-mbp51-extreme-[0-9]*-x86_64.pkg.tar.zst)
headers=("$dist"/linux-mbp51-extreme-headers-[0-9]*-x86_64.pkg.tar.zst)
[[ ${#kernels[@]} -eq 1 && ${#headers[@]} -eq 1 ]] || exit 2
echo "Verified kernel ABI: $release"
echo "Phase 2 for EndeavourOS: install packages, build patched wl, Dracut, add Btrfs GRUB entry."
if [[ "$mode" == --plan ]]; then echo "Read-only; no changes made"; exit 0; fi
[[ -f /etc/arch-release ]] || { echo "Requires installed Arch Linux"; exit 2; }
[[ "$(findmnt -no FSTYPE /)" == btrfs &&
   "$(findmnt -T /boot -n -o FSTYPE)" == btrfs &&
   "$(findmnt -no FSTYPE /boot/efi)" == vfat ]] || {
  echo "Expected EndeavourOS: Btrfs / and /boot, FAT32 /boot/efi" >&2; exit 2;
}
[[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" == MacBookPro5,1 ]] || {
  echo "Not the target MacBookPro5,1" >&2; exit 2;
}
command -v dracut >/dev/null || { echo "Dracut not installed" >&2; exit 2; }
[[ -s /boot/vmlinuz-linux-lts && -s /boot/initramfs-linux-lts.img &&
   -s /boot/grub/grub.cfg ]] || { echo "Stock LTS rescue entry missing"; exit 2; }
# GRUB index zero selects the new custom kernel because it sorts ahead of LTS.
# Refuse to install until stock LTS is the explicitly selected default.
grep -Eq '^GRUB_DEFAULT=.*gnulinux-advanced-.*>gnulinux-linux-lts-advanced-' /etc/default/grub || {
  echo "Set GRUB_DEFAULT to the explicit advanced/linux-lts menu ID before installing." >&2
  echo "Check: sudo grep -E '^[[:space:]]*(menuentry|submenu) ' /boot/grub/grub.cfg" >&2
  exit 2
}
# Keep existing GRUB default unchanged; EndeavourOS may use saved/0 config.
# The new entry is appended by 41_mbp51-experimental after stock entries.
sudo pacman -U --noconfirm "${kernels[0]}" "${headers[0]}"
test -s "/usr/lib/modules/$release/build/Module.symvers"
bash "$repo/compat/broadcom/make-local-package.sh" "$release"
pkgdir="$repo/.work/broadcom/$release/package"
(cd "$pkgdir" && sha256sum -c module-package.sha256)
modules=("$pkgdir"/mbp51-broadcom-wl-*.pkg.tar.zst)
[[ ${#modules[@]} -eq 1 ]] || { echo "Wrong private wl package count"; exit 1; }
sudo pacman -U --noconfirm "${modules[0]}"
sudo depmod -a "$release"
actual=$(modinfo -k "$release" -n wl)
expected="/usr/lib/modules/$release/updates/mbp51/wl.ko"
# EndeavourOS may report /lib instead of its canonical /usr/lib symlink target.
[[ -f "$actual" && "$(readlink -f "$actual")" == "$(readlink -f "$expected")" ]] || {
  echo "Wrong selected wl module: $actual (expected $expected)" >&2; exit 1;
}
vermagic=$(modinfo -k "$release" -F vermagic wl)
[[ "$vermagic" == "$release "* ]] || {
  echo "Wrong wl vermagic: $vermagic" >&2; exit 1;
}
sudo install -Dm644 "/usr/lib/modules/$release/vmlinuz" /boot/mbp51/vmlinuz
# Host-only primary shrinks startup image. Preserve a generic recovery initramfs.
sudo dracut --force --hostonly --kver "$release" /boot/mbp51/initramfs.img
sudo dracut --force --no-hostonly --kver "$release" /boot/mbp51/initramfs-fallback.img
[[ -s /boot/mbp51/vmlinuz && -s /boot/mbp51/initramfs.img &&
   -s /boot/mbp51/initramfs-fallback.img ]] || exit 1
root_uuid=$(findmnt -no UUID /)
boot_uuid=$(findmnt -T /boot -n -o UUID)
subvol=$(findmnt -no OPTIONS / | tr ',' '\n' | sed -n 's/^subvol=//p')
[[ "$boot_uuid" == "$root_uuid" && "$subvol" == /* && "$subvol" != *" "* ]] || {
  echo "Cannot identify actual Btrfs subvolume and root UUID" >&2; exit 1;
}
[[ "$boot_uuid" =~ ^[A-Fa-f0-9-]+$ && "$root_uuid" =~ ^[A-Fa-f0-9-]+$ ]] || {
  echo "Unexpected root or EFI UUID format"; exit 1;
}
# Dracut handles microcode; no separate Intel microcode image needed.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<EOF
#!/bin/sh
# Deliberately after 10_linux; LTS stays GRUB_DEFAULT=0.
cat <<'MBP51_GRUB'
menuentry 'MacBookPro5,1 experimental Linux 7.4-development v2' --id=mbp51-experimental-v2 {
  insmod part_gpt
  insmod btrfs
  search --no-floppy --fs-uuid --set=root $boot_uuid
  linux $subvol/boot/mbp51/vmlinuz root=UUID=$root_uuid rootflags=subvol=$subvol rw
  initrd $subvol/boot/mbp51/initramfs.img
}
menuentry 'MacBookPro5,1 experimental Linux 7.4-development v2 (generic fallback)' --id=mbp51-experimental-v2-fallback {
  insmod part_gpt
  insmod btrfs
  search --no-floppy --fs-uuid --set=root $boot_uuid
  linux $subvol/boot/mbp51/vmlinuz root=UUID=$root_uuid rootflags=subvol=$subvol rw
  initrd $subvol/boot/mbp51/initramfs-fallback.img
}
MBP51_GRUB
EOF
sudo install -m755 "$tmp" /etc/grub.d/41_mbp51-experimental
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub.cfg
sudo grep -Fq 'MacBookPro5,1 experimental Linux 7.4-development v2' /boot/grub/grub.cfg
echo "PASS: Linux 7.4-development v2 and patched wl installed; explicit LTS default retained."
echo "Reboot and MANUALLY choose experimental from GRUB."
