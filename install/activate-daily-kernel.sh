#!/usr/bin/env bash
# Install one isolated Daily, BORE, or Extreme Lab kernel. Never overwrites legacy
# /boot/mbp51 files. Direct invocation defaults to Daily for compatibility;
# activate-bore-kernel.sh and activate-lab-kernel.sh select their tiers.
# Run unprivileged. --plan is read-only; --install requires sudo.
#
# Options may appear in any order:
#   --plan [DIST_DIR]     verify only, change nothing
#   --install [DIST_DIR]  install kernel, headers, boot entry, then Wi-Fi
#   --no-wifi             skip the proprietary Broadcom module entirely. The
#                         kernel becomes bootable with Ethernet only, which is
#                         how a kernel should be qualified: the fragile vendor
#                         module must not gate whether an experiment can boot.
#   --wifi-only           build/install only the matching private wl.ko for an
#                         already-installed kernel; touch no package or entry.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
export MBP51_TIER=${MBP51_TIER:-daily}
source "$root/scripts/tier-profile.sh"

usage() {
  cat >&2 <<EOF
Usage: $0 [--plan|--install] [DIST_DIR] [--no-wifi] [--wifi-only]

  --plan        Verify the artifact directory and print the plan. No changes.
  --install     Install kernel + headers, create the boot entry, then Wi-Fi.
  --no-wifi     Skip Broadcom. Kernel stays bootable (use Ethernet).
  --wifi-only   Only build/install the matching wl.ko for an installed kernel.
  DIST_DIR      Artifact directory (default: $root/dist/\$MBP51_TIER)

Tier: $MBP51_TIER   ABI: $MBP51_KERNEL_RELEASE
EOF
}

mode=""
install_wifi=1
wifi_only=0
dist=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) mode=--plan; shift ;;
    --install) mode=--install; shift ;;
    --no-wifi) install_wifi=0; shift ;;
    --wifi-only) wifi_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)
      [[ -z "$dist" ]] || { echo "Unexpected extra argument: $1" >&2; usage; exit 2; }
      dist=$1; shift ;;
  esac
done
# Default mode: --plan normally, but --wifi-only implies --install because
# skipping it would make the flag do nothing.
if [[ -z "$mode" ]]; then
  if (( wifi_only )); then mode=--install; else mode=--plan; fi
fi
dist=${dist:-"$root/dist/$MBP51_TIER"}
[[ "$mode" == --plan || "$mode" == --install ]] || {
  echo "Pick --plan or --install, not both." >&2; exit 2;
}
(( ! (wifi_only && install_wifi == 0) )) || {
  echo "--wifi-only and --no-wifi contradict each other." >&2; exit 2;
}
[[ "$EUID" != 0 ]] || { echo "Run as an ordinary user." >&2; exit 2; }
bash "$root/scripts/verify-artifacts.sh" "$dist"
release=$(< "$dist/kernelrelease.txt")
[[ "$release" == "$MBP51_KERNEL_RELEASE" ]] || {
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
if (( wifi_only )); then
  echo "Mode: Wi-Fi only. Kernel packages and the boot entry are not touched."
elif (( install_wifi == 0 )); then
  echo "Mode: no Wi-Fi. Broadcom is skipped; use Ethernet on this kernel."
fi
if [[ "$mode" == --plan ]]; then
  echo "Read-only package verification succeeded; no installation attempted."
  exit 0
fi
[[ -f /etc/arch-release ]] || { echo "Requires Arch/EndeavourOS" >&2; exit 2; }
[[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" == MacBookPro5,1 ]] || {
  echo "Wrong machine"; exit 2;
}
for cmd in sudo pacman dracut depmod modinfo sha256sum findmnt \
  grub-probe grub-mkrelpath grub-mkconfig grub-script-check readlink; do
  command -v "$cmd" >/dev/null || { echo "Missing command: $cmd" >&2; exit 2; }
done
[[ "$(findmnt -no FSTYPE /)" == btrfs ]] || {
  echo "Expected a Btrfs root (required for rootflags=subvol=)." >&2; exit 2;
}
[[ -s /boot/grub/grub.cfg ]] || { echo "Missing /boot/grub/grub.cfg" >&2; exit 2; }
grep -Eq '^GRUB_DEFAULT=.*gnulinux-advanced-.*>gnulinux-linux-lts-advanced-' /etc/default/grub || {
  echo "Set an explicit linux-lts GRUB_DEFAULT before installation." >&2; exit 2;
}

# ---------------------------------------------------------------------------
# Kernel packages and boot entry. This happens BEFORE the proprietary Wi-Fi
# module: a kernel you can boot over Ethernet is strictly more useful than an
# installed package with no menu entry, and a Broadcom compile failure must not
# be able to hide the kernel's own qualification result.
# ---------------------------------------------------------------------------
boot_dir=/boot/mbp51/$MBP51_BOOT_SUBDIR
if (( ! wifi_only )); then
  [[ "$(findmnt -T /boot -no FSTYPE)" == btrfs &&
     "$(findmnt -no FSTYPE /boot/efi)" == vfat ]] || {
    echo "Expected EFI + Btrfs /boot." >&2; exit 2;
  }
  [[ -s /boot/vmlinuz-linux-lts && -s /boot/initramfs-linux-lts.img ]] || {
    echo "Stock LTS rescue missing"; exit 2;
  }
  sudo -v
  sudo pacman -U --noconfirm "${kernels[0]}" "${headers[0]}"
  [[ -s "/usr/lib/modules/$release/build/Module.symvers" ]] || {
    echo "Kernel/headers Module.symvers missing"; exit 1;
  }
  sudo install -Dm644 "/usr/lib/modules/$release/vmlinuz" "$boot_dir/vmlinuz"
  sudo dracut --force --hostonly --kver "$release" "$boot_dir/initramfs.img"
  sudo dracut --force --no-hostonly --kver "$release" "$boot_dir/initramfs-fallback.img"
  [[ -s "$boot_dir/vmlinuz" && -s "$boot_dir/initramfs.img" &&
     -s "$boot_dir/initramfs-fallback.img" ]] || {
    echo "Boot files were not produced in $boot_dir" >&2; exit 1;
  }

  # Ask GRUB how it sees these paths instead of assembling "$subvol/boot/..."
  # by hand. The hand-built form is only correct when /boot lives in the same
  # Btrfs subvolume as /, and it failed silently when it did not. This is the
  # same method install/activate-endeavouros-kernel.sh already used.
  boot_uuid=$(sudo grub-probe -t fs_uuid "$boot_dir/vmlinuz")
  boot_fs=$(sudo grub-probe -t fs "$boot_dir/vmlinuz")
  kernel_path=$(sudo grub-mkrelpath "$boot_dir/vmlinuz")
  initrd_path=$(sudo grub-mkrelpath "$boot_dir/initramfs.img")
  initrd_fallback_path=$(sudo grub-mkrelpath "$boot_dir/initramfs-fallback.img")
  root_uuid=$(findmnt -no UUID /)
  subvol=$(findmnt -no OPTIONS / | tr ',' '\n' | sed -n 's/^subvol=//p')
  [[ "$boot_uuid" =~ ^[A-Za-z0-9-]+$ && "$root_uuid" =~ ^[A-Za-z0-9-]+$ &&
     "$boot_fs" =~ ^(btrfs|ext2|ext3|ext4|fat)$ &&
     "$kernel_path" == /* && "$initrd_path" == /* &&
     "$initrd_fallback_path" == /* ]] || {
    echo "GRUB could not resolve the boot paths for $boot_dir" >&2
    echo "boot_uuid=$boot_uuid fs=$boot_fs kernel=$kernel_path" >&2
    exit 1
  }
  # rootflags=subvol= is only emitted when / is itself a subvolume mount.
  [[ "$subvol" == /* && "$subvol" != *" "* ]] || {
    echo "Cannot identify the Btrfs subvolume of / (got '$subvol')" >&2; exit 1
  }
  echo "Boot paths: kernel=$kernel_path  fs=$boot_fs  uuid=$boot_uuid  subvol=$subvol"

  entry=$(mktemp)
  trap 'rm -f "$entry"' EXIT
  cat > "$entry" <<EOF
#!/bin/sh
cat <<'MBP51_TIER_GRUB'
menuentry '$MBP51_GRUB_TITLE' --id=$MBP51_GRUB_ID {
  insmod part_gpt
  insmod $boot_fs
  search --no-floppy --fs-uuid --set=root $boot_uuid
  linux $kernel_path root=UUID=$root_uuid rootflags=subvol=$subvol rw
  initrd $initrd_path
}
menuentry '$MBP51_GRUB_TITLE (generic recovery)' --id=$MBP51_GRUB_ID-fallback {
  insmod part_gpt
  insmod $boot_fs
  search --no-floppy --fs-uuid --set=root $boot_uuid
  linux $kernel_path root=UUID=$root_uuid rootflags=subvol=$subvol rw
  initrd $initrd_fallback_path
}
MBP51_TIER_GRUB
EOF
  sudo install -m755 "$entry" "/etc/grub.d/42_mbp51-$MBP51_TIER"
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  sudo grub-script-check /boot/grub/grub.cfg
  sudo grep -Fq "$MBP51_GRUB_TITLE" /boot/grub/grub.cfg || {
    echo "Menu entry did not reach grub.cfg" >&2; exit 1;
  }
  grep -Eq '^GRUB_DEFAULT=.*gnulinux-advanced-.*>gnulinux-linux-lts-advanced-' /etc/default/grub || {
    echo "GRUB default drifted; resolve before rebooting" >&2; exit 1;
  }
  echo "BOOTABLE: $release is in the menu; linux-lts is still the default."
fi

# ---------------------------------------------------------------------------
# Proprietary Broadcom module. Built on this machine only; never distributed.
# ---------------------------------------------------------------------------
if (( install_wifi )); then
  [[ -s "/usr/lib/modules/$release/build/Module.symvers" ]] || {
    echo "Kernel headers for $release are not installed; cannot build wl.ko." >&2
    echo "Install the kernel first: $0 --install $dist" >&2
    exit 2
  }
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
  echo "WI-FI: $MBP51_WL_PKGNAME installed and resolving to the private path."
else
  echo "WI-FI: skipped (--no-wifi). Wi-Fi will not work on $release."
  echo "Add it later without touching packages or GRUB:"
  echo "  bash $0 --wifi-only $dist"
fi

if (( wifi_only )); then
  echo "PASS: matching private wl.ko installed for $release; kernel and boot entry untouched."
  exit 0
fi
echo "PASS: $MBP51_TIER kernel added beside legacy and LTS; LTS still explicitly configured as default."
echo "Select $MBP51_TIER manually at GRUB for physical qualification."
