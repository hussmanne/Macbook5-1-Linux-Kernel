#!/usr/bin/env bash
# Install one isolated Daily, BORE, or Extreme Lab kernel. Never overwrites legacy
# /boot/mbp51 files. Direct invocation defaults to Daily for compatibility;
# activate-bore-kernel.sh and activate-lab-kernel.sh select their tiers.
# Run unprivileged. --plan is read-only; --install requires sudo.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
export MBP51_TIER=${MBP51_TIER:-daily}
source "$root/scripts/tier-profile.sh"
mode=${1:---plan}
dist=${2:-"$root/dist/$MBP51_TIER"}
[[ "$mode" == --plan || "$mode" == --install ]] || {
  echo "Usage: $0 --plan [DIST_DIR] | --install [DIST_DIR]" >&2; exit 2;
}
[[ "$EUID" != 0 ]] || { echo "Run as an ordinary user." >&2; exit 2; }
bash "$root/scripts/verify-artifacts.sh" "$dist"
release=$(< "$dist/kernelrelease.txt")
[[ "$release" == "7.3.0$KERNEL_LOCALVERSION" ]] || {
  echo "Unexpected $MBP51_TIER ABI: $release" >&2; exit 2;
}
shopt -s nullglob
kernels=("$dist"/"$MBP51_PKGBASE"-[0-9]*-x86_64.pkg.tar.zst)
headers=("$dist"/"$MBP51_PKGBASE"-headers-[0-9]*-x86_64.pkg.tar.zst)
[[ ${#kernels[@]} == 1 && ${#headers[@]} == 1 ]] || exit 2
echo "$MBP51_TIER ABI: $release"
echo "Package: ${kernels[0]}"
echo "Headers: ${headers[0]}"
echo "Stock linux-lts, legacy kernel, and other custom tiers remain untouched."
if [[ "$mode" == --plan ]]; then
  echo "Read-only package verification succeeded; no installation attempted."
  exit 0
fi
[[ -f /etc/arch-release ]] || { echo "Requires Arch/EndeavourOS" >&2; exit 2; }
[[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" == MacBookPro5,1 ]] || {
  echo "Wrong machine"; exit 2;
}
for cmd in sudo pacman dracut depmod modinfo sha256sum findmnt grub-mkconfig grub-script-check readlink; do
  command -v "$cmd" >/dev/null || { echo "Missing command: $cmd" >&2; exit 2; }
done
[[ "$(findmnt -no FSTYPE /)" == btrfs &&
   "$(findmnt -T /boot -no FSTYPE)" == btrfs &&
   "$(findmnt -no FSTYPE /boot/efi)" == vfat ]] || {
  echo "Expected EFI + Btrfs root and boot." >&2; exit 2;
}
[[ -s /boot/vmlinuz-linux-lts && -s /boot/initramfs-linux-lts.img &&
   -s /boot/grub/grub.cfg ]] || { echo "Stock LTS rescue missing"; exit 2; }
grep -Eq '^GRUB_DEFAULT=.*gnulinux-advanced-.*>gnulinux-linux-lts-advanced-' /etc/default/grub || {
  echo "Set an explicit linux-lts GRUB_DEFAULT before installation." >&2; exit 2;
}
root_uuid=$(findmnt -no UUID /)
boot_uuid=$(findmnt -T /boot -no UUID)
subvol=$(findmnt -no OPTIONS / | tr ',' '\n' | sed -n 's/^subvol=//p')
[[ "$root_uuid" == "$boot_uuid" && "$root_uuid" =~ ^[0-9a-fA-F-]+$ &&
   "$subvol" == /* && "$subvol" != *" "* ]] || {
  echo "Unexpected root/boot UUID or Btrfs subvolume"; exit 2;
}
sudo -v
sudo pacman -U --noconfirm "${kernels[0]}" "${headers[0]}"
[[ -s "/usr/lib/modules/$release/build/Module.symvers" ]] || {
  echo "Kernel/headers Module.symvers missing"; exit 1;
}
# BCM4322 driver remains proprietary and is built solely on the MacBook.
MBP51_TIER="$MBP51_TIER" bash "$root/compat/broadcom/make-local-package.sh" "$release"
stage="$root/.work/broadcom/$release/package"
(cd "$stage" && sha256sum -c module-package.sha256)
wl_packages=("$stage"/"$MBP51_WL_PKGNAME"-[0-9]*-x86_64.pkg.tar.zst)
[[ ${#wl_packages[@]} == 1 ]] || { echo "Missing matching private WL package"; exit 1; }
sudo pacman -U --noconfirm "${wl_packages[0]}"
sudo depmod -a "$release"
module_file=$(modinfo -k "$release" -n wl)
expected="/usr/lib/modules/$release/updates/mbp51/wl.ko"
[[ -f "$module_file" && "$(readlink -f "$module_file")" == "$(readlink -f "$expected")" ]] || {
  echo "Wrong wl module: $module_file"; exit 1;
}
[[ "$(modinfo -k "$release" -F vermagic wl)" == "$release "* ]] || {
  echo "Wrong wl vermagic"; exit 1;
}
boot_dir=/boot/mbp51/$MBP51_BOOT_SUBDIR
sudo install -Dm644 "/usr/lib/modules/$release/vmlinuz" "$boot_dir/vmlinuz"
sudo dracut --force --hostonly --kver "$release" "$boot_dir/initramfs.img"
sudo dracut --force --no-hostonly --kver "$release" "$boot_dir/initramfs-fallback.img"
[[ -s "$boot_dir/vmlinuz" && -s "$boot_dir/initramfs.img" &&
   -s "$boot_dir/initramfs-fallback.img" ]] || exit 1
# Write independent custom-menu file; NEVER replace the legacy menu.
entry=$(mktemp)
trap 'rm -f "$entry"' EXIT
cat > "$entry" <<EOF
#!/bin/sh
cat <<'MBP51_TIER_GRUB'
menuentry '$MBP51_GRUB_TITLE' --id=$MBP51_GRUB_ID {
  insmod part_gpt
  insmod btrfs
  search --no-floppy --fs-uuid --set=root $boot_uuid
  linux $subvol/boot/mbp51/$MBP51_BOOT_SUBDIR/vmlinuz root=UUID=$root_uuid rootflags=subvol=$subvol rw
  initrd $subvol/boot/mbp51/$MBP51_BOOT_SUBDIR/initramfs.img
}
menuentry '$MBP51_GRUB_TITLE (generic recovery)' --id=$MBP51_GRUB_ID-fallback {
  insmod part_gpt
  insmod btrfs
  search --no-floppy --fs-uuid --set=root $boot_uuid
  linux $subvol/boot/mbp51/$MBP51_BOOT_SUBDIR/vmlinuz root=UUID=$root_uuid rootflags=subvol=$subvol rw
  initrd $subvol/boot/mbp51/$MBP51_BOOT_SUBDIR/initramfs-fallback.img
}
MBP51_TIER_GRUB
EOF
sudo install -m755 "$entry" "/etc/grub.d/42_mbp51-$MBP51_TIER"
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo grub-script-check /boot/grub/grub.cfg
sudo grep -Fq "$MBP51_GRUB_TITLE" /boot/grub/grub.cfg
grep -Eq '^GRUB_DEFAULT=.*gnulinux-advanced-.*>gnulinux-linux-lts-advanced-' /etc/default/grub || {
  echo "GRUB default drifted; resolve before rebooting" >&2; exit 1;
}
echo "PASS: $MBP51_TIER kernel added beside legacy and LTS; LTS still explicitly configured as default."
echo "Select $MBP51_TIER manually at GRUB for physical qualification."
