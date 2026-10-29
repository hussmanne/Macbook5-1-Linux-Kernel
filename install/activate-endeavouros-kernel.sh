#!/usr/bin/env bash
# EndeavourOS GRUB+dracut activation of the pinned MacBookPro5,1 kernel.
# This is separate from the vanilla-Arch mkinitcpio helper.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
export MBP51_TIER=${MBP51_TIER:-legacy}
source "$repo/scripts/tier-profile.sh"
mode=${1:---plan}
dist=${2:-"$repo/dist"}
[[ "$mode" == --plan || "$mode" == --install ]] || {
  echo "Usage: bash $0 --plan [DIST_DIR] | --install [DIST_DIR]" >&2; exit 2;
}
[[ "$EUID" -ne 0 ]] || {
  echo "Run as an ordinary user; this helper invokes sudo for installation." >&2; exit 2;
}
bash "$repo/scripts/verify-artifacts.sh" "$dist"
release=$(cat "$dist/kernelrelease.txt")
[[ "$release" == "$MBP51_KERNEL_RELEASE" ]] || {
  echo "Artifact doesn't match pinned source.lock." >&2; exit 2;
}
shopt -s nullglob
kernel=("$dist"/linux-mbp51-extreme-[0-9]*-x86_64.pkg.tar.zst)
headers=("$dist"/linux-mbp51-extreme-headers-[0-9]*-x86_64.pkg.tar.zst)
[[ ${#kernel[@]} -eq 1 && ${#headers[@]} -eq 1 ]] || {
  echo "Exactly one kernel and header package are required." >&2; exit 2;
}
echo "Verified development kernel: $release"
echo "EndeavourOS integration: GRUB + dracut; leave installed kernels bootable."
if [[ "$mode" == --plan ]]; then
  echo "Read-only preflight complete. No changes made."
  exit 0
fi
[[ -r /etc/os-release ]] || { echo "Missing os-release" >&2; exit 2; }
source /etc/os-release
[[ "${ID:-}" == endeavouros ]] || {
  echo "Requires installed EndeavourOS; use original Arch helper for vanilla Arch." >&2; exit 2;
}
for cmd in sudo pacman dracut grub-probe grub-mkrelpath grub-mkconfig \
  grub-script-check findmnt modinfo depmod sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Missing required tool: $cmd" >&2; exit 2; }
done
[[ "$(findmnt -no FSTYPE /)" == btrfs ]] || {
  echo "This path supports unencrypted Calamares Btrfs root only." >&2; exit 2;
}
opts=$(findmnt -no OPTIONS /)
[[ ",$opts," == *",subvol=/@,"* || ",$opts," == *",subvol=@,"* ]] || {
  echo "Expected default Btrfs root subvolume @; actual: $opts" >&2; exit 2;
}
[[ -r /boot/grub/grub.cfg && -d /etc/grub.d &&
   -s /boot/vmlinuz-linux-lts ]] || {
  echo "Missing GRUB configuration or a stock Arch LTS rescue kernel." >&2; exit 2;
}
# Default entry 0 remains the existing regular EndeavourOS kernel.
grep -Eq '^GRUB_DEFAULT="?0"?$' /etc/default/grub || {
  echo "Require GRUB_DEFAULT=0 to keep the existing kernel as default." >&2; exit 2;
}
[[ ! -d /sys/class/block/dm-0/slaves ]] || {
  echo "Device-mapper root detected. Encrypted/LVM installations need manual review." >&2; exit 2;
}
echo "Existing rescue kernel and GRUB confirmed. Installing pinned packages..."
sudo pacman -S --needed --noconfirm base-devel python kmod broadcom-wl-dkms
sudo pacman -U --noconfirm "${kernel[0]}" "${headers[0]}"
[[ -s "/usr/lib/modules/$release/build/Module.symvers" &&
   -s "/usr/lib/modules/$release/vmlinuz" ]] || {
  echo "Installed kernel and headers are incomplete." >&2; exit 1;
}
bash "$repo/compat/broadcom/make-local-package.sh" "$release"
pkgdir="$repo/.work/broadcom/$release/package"
(cd "$pkgdir" && sha256sum -c module-package.sha256)
packages=("$pkgdir"/mbp51-broadcom-wl-*.pkg.tar.zst)
[[ ${#packages[@]} -eq 1 ]] || { echo "Wrong Broadcom package count." >&2; exit 1; }
sudo pacman -U --noconfirm "${packages[0]}"
sudo depmod -a "$release"
selected=$(modinfo -k "$release" -n wl)
[[ "$selected" == "/usr/lib/modules/$release/updates/mbp51/wl.ko" ]] || {
  echo "Broadcom selection conflicts: $selected; do not boot custom kernel." >&2; exit 1;
}
vermagic=$(modinfo -k "$release" -F vermagic wl)
[[ "$vermagic" == "$release "* ]] || {
  echo "Broadcom vermagic mismatches: $vermagic" >&2; exit 1;
}
# Dracut's standalone explicit-kver mode works without EOS's stock
# kernel-image packaging hooks and does not change stock initramfs files.
sudo install -Dm644 "/usr/lib/modules/$release/vmlinuz" /boot/mbp51/vmlinuz
sudo dracut --force --no-hostonly --early-microcode \
  /boot/mbp51/initramfs.img "$release"
[[ -s /boot/mbp51/vmlinuz && -s /boot/mbp51/initramfs.img ]] || {
  echo "Could not create custom kernel + initramfs." >&2; exit 1;
}
root_uuid=$(findmnt -no UUID /)
boot_uuid=$(grub-probe -t fs_uuid /boot/mbp51/vmlinuz)
boot_fs=$(grub-probe -t fs /boot/mbp51/vmlinuz)
kernel_path=$(grub-mkrelpath /boot/mbp51/vmlinuz)
initrd_path=$(grub-mkrelpath /boot/mbp51/initramfs.img)
[[ "$root_uuid" =~ ^[A-Za-z0-9-]+$ &&
   "$boot_uuid" =~ ^[A-Za-z0-9-]+$ &&
   "$boot_fs" =~ ^(btrfs|ext2|fat)$ &&
   "$kernel_path" == /* && "$initrd_path" == /* ]] || {
  echo "GRUB paths/filesystem UUIDs could not be verified." >&2; exit 1;
}
temp=$(mktemp)
trap 'rm -f "$temp"' EXIT
cat > "$temp" <<EOF
#!/bin/sh
# Manually selectable; after distro entries, never the GRUB_DEFAULT=0 entry.
cat <<'MBP51_GRUB'
menuentry 'MacBookPro5,1 Linux 7.4-development (experimental)' --id=mbp51-experimental {
  insmod $boot_fs
  search --no-floppy --fs-uuid --set=root $boot_uuid
  linux $kernel_path root=UUID=$root_uuid rootflags=subvol=@ rw
  initrd $initrd_path
}
MBP51_GRUB
EOF
sudo install -m755 "$temp" /etc/grub.d/41_mbp51-experimental
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub.cfg
grep -Fq "MacBookPro5,1 Linux 7.4-development (experimental)" /boot/grub/grub.cfg
grep -Eq '^GRUB_DEFAULT="?0"?$' /etc/default/grub
echo "PASS: experimental kernel and matching Broadcom wl installed with dracut."
echo "EndeavourOS and LTS rescue kernels remain intact; existing boot default unchanged."
echo "Manually select the experimental entry in GRUB for first hardware boot."
