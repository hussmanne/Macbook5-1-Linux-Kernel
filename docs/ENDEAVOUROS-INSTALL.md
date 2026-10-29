# EndeavourOS + experimental MacBookPro5,1 kernel

The Windows-created EndeavourOS Titan Nova ISO is an installer only.
It does NOT contain the custom kernel or modified Broadcom STA driver.

## Install EndeavourOS first

Use the official ISO, Calamares ONLINE installation, LXQt desktop, GRUB
bootloader, unencrypted Btrfs and erase ONLY the ADATA SU635 internal SSD.
The current MX USB can be overwritten by Rufus in DD mode.
The EndeavourOS ISO may lack proprietary BCM4322 wl support; an Ethernet
connection is recommended while installing. Boot with Apple Option/Alt key.
Run the normal Nouveau graphics option (never the modern proprietary NVIDIA
boot option for 9400M/9600M GT).

Once the freshly installed stock EndeavourOS desktop boots:

    sudo pacman -Syu
    sudo pacman -S --needed linux-lts linux-lts-headers base-devel python kmod broadcom-wl-dkms
    sudo dracut-rebuild
    sudo grub-mkconfig -o /boot/grub/grub.cfg

Reboot and confirm the original EndeavourOS kernel and LTS are selectable
in GRUB. Do not uninstall either; both are rescue entries.

EndeavourOS uses dracut and eos-dracut when installed with GRUB, NOT
the mkinitcpio-only layout assumed by install/activate-custom-kernel.sh.
The correct EndeavourOS helper is install/activate-endeavouros-kernel.sh.
It deliberately checks GRUB_DEFAULT=0, Btrfs subvol @ and LTS existence.
Other filesystems, LUKS, LVM, systemd-boot and nondefault Btrfs layouts
need manual review, not automatic execution.

## Obtain the already-built pinned kernel

Latest successful exact-source build:
https://github.com/hussmanne/Macbook5-1-Linux-Kernel/actions/runs/40182567735

Download its mbp51-kernel-and-headers artifact, which contains BOTH
kernel and headers Arch pacman packages plus a manifest and checksums.
Unzip the artifact into the cloned repository's dist directory.
Do not use files from another source.lock.

    git clone https://github.com/hussmanne/Macbook5-1-Linux-Kernel.git
    cd Macbook5-1-Linux-Kernel
    bash scripts/verify-artifacts.sh dist
    bash install/activate-endeavouros-kernel.sh --plan dist

When the checks succeed, run as an ORDINARY user:

    bash install/activate-endeavouros-kernel.sh --install dist

The helper installs the pinned kernel and matching headers via pacman,
builds Broadcom STA wl.ko locally from the Arch broadcom-wl-dkms sources
with source-locked compatibility patches, makes/installs its own
pacman-managed private package, checks vermagic and depmod selection,
creates /boot/mbp51/vmlinuz and /boot/mbp51/initramfs.img using
dracut with an explicit kernel release, then adds an experimental
GRUB menuentry after the regular distro entries. It does NOT replace
GRUB_DEFAULT=0, remove EndeavourOS kernel(s), or require reboot.

The published artifact is not a universally ready-to-install boot ISO.
The proprietary Broadcom wl module is built on the installed machine,
not distributed in our public CI artifact.

## Qualification

The custom kernel ABI is 7.3.0-mbp51-extreme-g21a7f44f-v2-c2 because the pinned
Linux 7.4 development snapshot still reports 7.3.0 in its Makefile.
It is not the 7.4 tagged release.

Reboot and manually select the experimental GRUB entry. Use:

    uname -r
    lspci -nnk
    nmcli device status
    modinfo wl | grep -E 'filename|vermagic'
    journalctl -k -b --no-pager | tail -n 100

Verify full screen at 1440x900, Nouveau 9400M/9600M GT, BCM4322 WPA2
association and reconnect, audio, input, fans/temps, battery reporting,
forcedeth Ethernet and manual S3 suspend/resume while on AC power.
Boot the normal kernel if any critical component is unreliable.

After baseline qualification, optionally deploy runtime/ power settings
(including global PowerTOP auto-tune at startup and after wake); do NOT
enable them during the first experimental boot. The custom binary has
CONFIG_CPU_MITIGATIONS=n, deliberately reducing speculative attack
mitigations compared with stock Linux.
