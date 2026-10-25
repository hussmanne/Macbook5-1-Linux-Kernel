# Arch SSD installation and custom-kernel handoff

**User decision:** use the existing 7.5 GiB USB as temporary installer;
erase internal ADATA SU635 240 GB SSD (223.57 GiB, APFS/macOS currently).
Do NOT install the permanent OS on the slow USB 2.0 stick.

## Flash Arch ISO from macOS

Download official ISO at https://archlinux.org/download/ .
The 2026.10.01 ISO SHA256 is:
684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5

In macOS Terminal, confirm the **7.5 GB external** target, not internal SSD:

    cd ~/Downloads
    shasum -a 256 archlinux-2026.10.01-x86_64.iso
    diskutil list
    diskutil unmountDisk /dev/diskN
    sudo dd if=archlinux-2026.10.01-x86_64.iso of=/dev/rdiskN bs=4m
    sync
    diskutil eject /dev/diskN

Replace diskN with the verified USB device. This overwrites MX LiveUSB.
The Arch Wiki documents this procedure:
https://wiki.archlinux.org/title/USB_flash_installation_medium

## Install to the internal SSD

Boot USB holding Option/Alt on Mac and select EFI Boot. Use AC power.
**Network required**: official Arch ISO may not include the proprietary
Broadcom wl driver. Have Ethernet available. No network = do not wipe SSD.

    ip link
    ping -c 2 archlinux.org
    git clone https://github.com/hussmanne/Macbook5-1-Linux-Kernel.git
    cd Macbook5-1-Linux-Kernel
    bash install/archiso-install.sh --plan /dev/sda
    bash install/archiso-install.sh --execute /dev/sda mbp

Arch ISO normally runs as root. The script checks MacBookPro5,1 and
ADATA SU635 disk model/size, refuses removable or mounted drives,
and demands typed `ERASE-ADATA-SU635` confirmation. It wipes the
old EFI/APFS partitions and installs signed official rolling Arch:
Btrfs root/home/snapshots, FAT32 EFI + optional BIOS boot partition,
LXQt 2.4/Openbox/X11, NetworkManager, PipeWire, LTS kernel with headers,
Arch stock Broadcom DKMS, zram, fstrim.timer. It creates user "mbp" and
prompts for a password. Global PowerTOP service is staged but NOT enabled
until first boot tests pass.

On success:

    sync
    umount -R /mnt
    reboot

Remove USB. Confirm LTS desktop, both Nouveau GPUs, keyboard/trackpad,
sound, Ethernet, Wi-Fi, suspend/wake, and thermal sensors.

## After the baseline works: add custom kernel

Download the exact successful `mbp51-kernel-and-headers` artifact:
https://github.com/hussmanne/Macbook5-1-Linux-Kernel/actions/runs/40175619281
(GitHub may require a logged-in browser.)

The installer copied the repository into the new user's home directory.
On installed Arch, download/unzip the artifact into `~/Macbook5-1-Linux-Kernel/dist/`.
The exact downloaded kernel archive is not bundled with the ISO.

    bash scripts/verify-artifacts.sh dist

Then verify the artifact and activate the custom kernel from the
**already-booted LTS Arch desktop, as an ordinary user**:

    cd ~/Macbook5-1-Linux-Kernel
    bash scripts/verify-artifacts.sh dist
    bash install/activate-custom-kernel.sh --plan dist
    bash install/activate-custom-kernel.sh --install dist

The activation script installs exact matching headers and kernel,
builds proprietary `wl.ko` locally (without redistributing it), installs
a pacman-managed Broadcom module, and creates a **manual GRUB menu entry**
under /boot/mbp51. Stock Arch LTS remains menu entry zero and default.
Do not try the custom kernel before the baseline LTS boot works.

After confirming the custom boot, apply requested global startup/resume
PowerTOP tuning:

    sudo systemctl enable --now mbp51-powertop.service

Keep a record of baseline Wi-Fi and USB/suspend behavior before enabling.
The experimental kernel sets CONFIG_CPU_MITIGATIONS=n by user choice;
stock LTS retains normal mitigations and remains the boot fallback.
