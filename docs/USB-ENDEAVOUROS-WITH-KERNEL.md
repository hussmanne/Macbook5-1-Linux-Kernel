# Windows: one bootable EndeavourOS USB carrying our custom kernel

GitHub Actions workflow "Build EndeavourOS USB with preloaded MBP51
kernel" remixes the SHA512-verified official Titan Nova ISO using
xorriso's hybrid-boot replay. It adds the source-pinned kernel and
headers packages, verification and activation scripts as /MBP51 on
the same bootable ISO. It preserves official EndeavourOS's default live
kernel, Calamares and BIOS/UEFI bootloader. This is **not yet the
experimental kernel as live boot** and is not a no-click auto-install.

The correct artifact is **EndeavourOS-Titan-Nova-MBP51-USB** produced
by this custom ISO workflow (not the standalone kernel artifact).
Download it in Windows, extract .iso and flash with Rufus in **DD
Image mode** to the existing >=8GB USB. Verify custom-iso.sha256 first.

Apple MacBookPro5,1: boot holding Option/Alt -> EFI Boot. Use Calamares
ONLINE, LXQt, GRUB and unencrypted Btrfs. Target the internal ADATA
SU635, which the user authorized erasing. An Ethernet connection may be
required, because the live boot does not include proprietary wl. Install
normal EndeavourOS and reboot once to verify its stock kernel.

Install a second rescue kernel:
    sudo pacman -Syu
    sudo pacman -S --needed linux-lts linux-lts-headers base-devel python kmod broadcom-wl-dkms
    sudo dracut-rebuild
    sudo grub-mkconfig -o /boot/grub/grub.cfg

Mount the still-inserted USB's ISO9660 volume, copy /MBP51 to your
home directory, and from the copied directory:
    cd ~/MBP51
    bash scripts/verify-artifacts.sh dist
    bash install/activate-endeavouros-kernel.sh --plan dist
    bash install/activate-endeavouros-kernel.sh --install dist

The compiler-based Broadcom driver is made on-device from the official
Arch broadcom-wl-dkms vendor sources; we do not distribute proprietary
compiled wl.ko. The experimental kernel stays a MANUAL GRUB option
while fallback kernels remain. Apply aggressive global PowerTOP only
after hardware qualification.

The remix changes the ISO and therefore has its OWN SHA256, not the
original EndeavourOS publisher signature. The workflow verifies the
official ISO SHA512, pinned packages, ISO EFI boot catalogue and
embedded kernelrelease, but real Mac boot is still unverified.
