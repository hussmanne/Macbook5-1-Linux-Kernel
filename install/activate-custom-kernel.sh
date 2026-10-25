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
echo "Phase 2: install both packages, privately compile and package wl, add GRUB entry."
if [[ "$mode" == --plan ]]; then echo "Read-only; no changes made"; exit 0; fi
[[ -f /etc/arch-release ]] || { echo "Requires installed Arch Linux"; exit 2; }
[[ "$(findmnt -no FSTYPE /)" == btrfs && "$(findmnt -no FSTYPE /boot/efi)" == vfat ]] || {
  echo "Expected Btrfs / and mounted FAT32 /boot/efi (EndeavourOS)" >&2; exit 2;
}
[[ "$(findmnt -no TARGET -T /boot)" == / ]] || {
  echo "Expected /boot stored within Btrfs root, not on separate partition" >&2; exit 2;
}
for tool in dracut grub-mkconfig grub-script-check modinfo depmod makepkg bsdtar; do
  command -v "$tool" >/dev/null || { echo "Required command unavailable: $tool" >&2; exit 2; }
done
[[ -d /usr/src ]] && compgen -G '/usr/src/broadcom-wl-*' >/dev/null || {
  echo "Install the Arch broadcom-wl-dkms source package before activation." >&2; exit 2;
}
# The running LTS kernel must remain in place to provide recovery and Wi-Fi.
[[ "$(uname -r)" == *-lts ]] || {
  echo "Boot the known-good LTS kernel before installing the experiment." >&2; exit 2;
}
[[ -s /boot/vmlinuz-linux-lts && -s /boot/initramfs-linux-lts.img &&
   -s /boot/grub/grub.cfg ]] || { echo "Stock LTS rescue entry missing"; exit 2; }
# Preserve EndeavourOS's current GRUB_DEFAULT unchanged; its value may be
# saved/menu-id based rather than literal zero.
[[ -r /etc/default/grub ]] || { echo "GRUB defaults missing"; exit 2; }
cp /etc/default/grub "$repo/.work-grub-defaults-before"
trap 'rm -f "$repo/.work-grub-defaults-before"' EXIT
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
[[ "$actual" == "/usr/lib/modules/$release/updates/mbp51/wl.ko" ]] || {
  echo "Wrong selected wl module: $actual"; exit 1;
}
sudo install -Dm644 "/usr/lib/modules/$release/vmlinuz" /boot/mbp51/vmlinuz
# Installed EndeavourOS uses Dracut rather than mkinitcpio.
sudo dracut --force --no-hostonly /boot/mbp51/initramfs.img "$release"
[[ -s /boot/mbp51/vmlinuz && -s /boot/mbp51/initramfs.img ]] || exit 1
root_uuid=$(findmnt -no UUID /)
root_options=$(findmnt -no OPTIONS /)
root_subvol=$(printf '%s\n' "$root_options" | tr ',' '\n' | sed -n 's/^subvol=//p' | head -n1)
[[ -n "$root_subvol" && "$root_subvol" == /* ]] || {
  echo "Could not detect mounted Btrfs subvolume in root options: $root_options" >&2; exit 1;
}
# The GRUB root is the Btrfs volume, NOT the separate FAT32 /boot/efi.
boot_uuid="$root_uuid"
[[ "$boot_uuid" =~ ^[A-Fa-f0-9-]+$ && "$root_uuid" =~ ^[A-Fa-f0-9-]+$ ]] || {
  echo "Unexpected root or EFI UUID format"; exit 1;
}
# Dracut assembles microcode in the initramfs when available.
ucode=''
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<EOF
#!/bin/sh
# Deliberately after 10_linux; existing EndeavourOS default unchanged.
cat <<'MBP51_GRUB'
menuentry 'MacBookPro5,1 experimental Linux 7.4-development' --id=mbp51-experimental {
  insmod part_gpt
  insmod btrfs
  search --no-floppy --fs-uuid --set=root $boot_uuid
  linux /boot/mbp51/vmlinuz root=UUID=$root_uuid rootflags=subvol=$root_subvol rw
  initrd /boot/mbp51/initramfs.img
}
MBP51_GRUB
EOF
sudo install -m755 "$tmp" /etc/grub.d/41_mbp51-experimental
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub.cfg
grep -Fq 'MacBookPro5,1 experimental Linux 7.4-development' /boot/grub/grub.cfg
cmp -s /etc/default/grub "$repo/.work-grub-defaults-before" || {
  echo "GRUB defaults changed unexpectedly; inspect before reboot" >&2; exit 1;
}
echo "PASS: custom kernel and Broadcom driver added; existing default preserved."
echo "Reboot and MANUALLY choose experimental from GRUB."
