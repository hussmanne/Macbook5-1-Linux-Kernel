#!/usr/bin/env bash
# Official Arch ISO only. Read-only by default; --execute wipes ADATA SU635.
set -euo pipefail
mode=--plan
disk=/dev/sda
user=mbp
[[ $# -lt 1 ]] || mode="$1"
[[ $# -lt 2 ]] || disk="$2"
[[ $# -lt 3 ]] || user="$3"
[[ "$mode" == --plan || "$mode" == --execute ]] || { echo "Usage: $0 --plan [DISK] | --execute DISK USER"; exit 2; }
[[ "$user" =~ ^[a-z_][a-z0-9_-]{0,30}$ && "$user" != root ]] || exit 2
[[ -b "$disk" ]] || { echo "Disk not found: $disk"; exit 2; }
disk=$(readlink -f "$disk")
[[ "$(lsblk -dn -o TYPE "$disk")" == disk ]] || { echo "Specify a complete disk"; exit 2; }
model=$(lsblk -dn -o MODEL "$disk")
bytes=$(lsblk -bdn -o SIZE "$disk")
removable=$(lsblk -dn -o RM "$disk")
machine=$(cat /sys/class/dmi/id/product_name 2>/dev/null || :)
[[ "$machine" == MacBookPro5,1 && "$model" == *SU635* && "$removable" == 0 &&
  "$bytes" -gt 225000000000 && "$bytes" -lt 260000000000 ]] || {
  printf 'REFUSING: machine=%s model=%s size=%s removable=%s\n' "$machine" "$model" "$bytes" "$removable" >&2
  exit 2
}
printf 'Target %s: %s %s bytes; %s\n' "$disk" "$model" "$bytes" "$machine"
echo "Arch LTS + LXQt/Openbox/X11 + Btrfs + EFI/BIOS GRUB; ALL APFS DATA ERASED"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$disk"
if [[ "$mode" == --plan ]]; then echo "Read-only plan: no changes made"; exit 0; fi
[[ "$EUID" -eq 0 && -d /run/archiso && -f /etc/arch-release ]] || {
  echo "EXECUTE ONLY IN THE OFFICIAL ARCH ISO AS ROOT" >&2; exit 2;
}
for cmd in sgdisk wipefs partprobe udevadm mkfs.fat mkfs.btrfs btrfs pacstrap genfstab arch-chroot; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd"; exit 2; }
done
if lsblk -nrpo MOUNTPOINTS "$disk" | grep -q '[^[:space:]]'; then
  echo "Target is mounted; unmount it first" >&2; exit 2
fi
[[ ! -e /mnt/etc/fstab ]] || { echo "Existing install mounted at /mnt"; exit 2; }
curl -fsSI --connect-timeout 10 --max-time 30 https://archlinux.org/ >/dev/null || {
  echo "No network. Arch ISO may require wired Ethernet for Broadcom BCM4322." >&2; exit 2;
}
read -r -p "Type ERASE-ADATA-SU635 to wipe $disk: " reply
[[ "$reply" == ERASE-ADATA-SU635 ]] || { echo "Cancelled"; exit 2; }
sgdisk --zap-all "$disk"
wipefs -af "$disk"
sgdisk --clear \
  --new=1:1MiB:+2MiB --typecode=1:EF02 --change-name=1:BIOS-GRUB \
  --new=2:0:+1024MiB --typecode=2:EF00 --change-name=2:MBP51-EFI \
  --new=3:0:0 --typecode=3:8300 --change-name=3:ARCH-ROOT "$disk"
partprobe "$disk"
udevadm settle
efi=$(lsblk -nrpo NAME,PARTN "$disk" | awk '$2==2 {print $1}')
rootdev=$(lsblk -nrpo NAME,PARTN "$disk" | awk '$2==3 {print $1}')
[[ -b "$efi" && -b "$rootdev" ]] || { echo "Partition enumeration failed"; exit 1; }
mkfs.fat -F32 -n MBP51EFI "$efi"
mkfs.btrfs -f -L MBP51ROOT "$rootdev"
mount "$rootdev" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
umount /mnt
mount -o noatime,compress=zstd:1,subvol=@ "$rootdev" /mnt
mkdir -p /mnt/boot /mnt/home /mnt/.snapshots
mount -o noatime,compress=zstd:1,subvol=@home "$rootdev" /mnt/home
mount -o noatime,compress=zstd:1,subvol=@snapshots "$rootdev" /mnt/.snapshots
mount "$efi" /mnt/boot
pacstrap -K /mnt \
 base base-devel linux-lts linux-lts-headers linux-firmware intel-ucode \
 mkinitcpio btrfs-progs dosfstools gptfdisk grub efibootmgr \
 networkmanager sudo git curl wget unzip nano vim less \
 bc bison flex dkms broadcom-wl-dkms kmod libelf openssl \
 xorg-server xorg-xinit xorg-xrandr xf86-input-libinput mesa mesa-utils \
 lxqt-session lxqt-panel lxqt-runner lxqt-config lxqt-globalkeys \
 lxqt-notificationd lxqt-powermanagement lxqt-policykit lxqt-qtplugin \
 lxqt-themes lxqt-sudo lxqt-archiver lxqt-admin pcmanfm-qt \
 qterminal openbox obconf-qt lximage-qt \
 lightdm lightdm-gtk-greeter xdg-user-dirs xdg-utils \
 pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils pavucontrol-qt \
 bluez bluez-utils blueman acpi upower lm_sensors smartmontools \
 zram-generator powertop firefox noto-fonts ttf-dejavu
genfstab -U /mnt > /mnt/etc/fstab
echo mbp51 > /mnt/etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 mbp51.localdomain mbp51\n' > /mnt/etc/hosts
ln -snf /usr/share/zoneinfo/America/Phoenix /mnt/etc/localtime
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo KEYMAP=us > /mnt/etc/vconsole.conf
arch-chroot /mnt locale-gen
arch-chroot /mnt hwclock --systohc
mkdir -p /mnt/etc/sudoers.d
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /mnt/etc/sudoers.d/10-wheel
chmod 440 /mnt/etc/sudoers.d/10-wheel
arch-chroot /mnt useradd -m -G wheel,video,audio,storage -s /bin/bash "$user"
mkdir -p "/mnt/home/$user/.config/lxqt"
printf '[General]\nwindow_manager=openbox\n' > "/mnt/home/$user/.config/lxqt/session.conf"
printf '[Desktop]\nSession=lxqt\n' > "/mnt/home/$user/.dmrc"
arch-chroot /mnt chown -R "$user:$user" "/home/$user"
echo "Enter password for new Arch user $user:"
arch-chroot /mnt passwd "$user"
sed -i -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' \
  -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=8/' \
  -e 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' \
  -e 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="rootflags=subvol=@"/' \
  /mnt/etc/default/grub
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot \
  --bootloader-id=MBP51 --removable --no-nvram
arch-chroot /mnt grub-install --target=i386-pc --recheck "$disk" ||
  echo "BIOS boot path unavailable; EFI fallback remains" >&2
arch-chroot /mnt mkinitcpio -P
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
repo_root=$(cd "$(dirname "$0")/.." && pwd)
install -Dm644 "$repo_root/runtime/systemd/zram-generator.conf" /mnt/etc/systemd/zram-generator.conf
install -Dm644 "$repo_root/runtime/sysctl.d/99-mbp51-memory.conf" /mnt/etc/sysctl.d/99-mbp51-memory.conf
install -Dm644 "$repo_root/runtime/systemd/mbp51-powertop.service" /mnt/etc/systemd/system/mbp51-powertop.service
install -Dm755 "$repo_root/runtime/system-sleep/50-mbp51-powertop" /mnt/usr/lib/systemd/system-sleep/50-mbp51-powertop
arch-chroot /mnt systemctl enable NetworkManager.service lightdm.service bluetooth.service fstrim.timer
arch-chroot /mnt test -s /boot/vmlinuz-linux-lts
arch-chroot /mnt test -s /boot/initramfs-linux-lts.img
arch-chroot /mnt test -s /boot/EFI/BOOT/BOOTX64.EFI
arch-chroot /mnt grub-script-check /boot/grub/grub.cfg
echo "PASS: Arch SSD installation complete. Default LTS boot preserved."
echo "sync; umount -R /mnt; reboot"
echo "Then run the separate experimental kernel activation procedure."
