#!/usr/bin/env bash
# Remaster the official ISO by ADDING packages and helpers to /MBP51/.
# Its proven stock live boot and Calamares remain unmodified.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test -s "$ORIGINAL_ISO"
test -s "$DIST_DIR/kernelrelease.txt"
test "$(basename "$ORIGINAL_ISO")" = EndeavourOS_Titan-Nova-2026.08.15.iso
echo "3f83bd745e9d5d518bdf6fc9a24092fb5347da449a6e109c6572bf999097b8b548c4cf1848fdfb3c7c2823f558c3f5b51a127060d9c5b81b9ad89b4041bee7fa  $ORIGINAL_ISO" | sha512sum -c -
bash "$root/scripts/verify-artifacts.sh" "$DIST_DIR"
K=$(cat "$DIST_DIR/kernelrelease.txt")
test "$K" = 7.3.0-mbp51-extreme-g21a7f44f
mkdir -p "$OUTPUT_DIR/kit/dist" "$OUTPUT_DIR/tmp"
git -C "$root" archive HEAD | tar -xf - -C "$OUTPUT_DIR/kit"
cp -a "$DIST_DIR"/. "$OUTPUT_DIR/kit/dist/"
cat > "$OUTPUT_DIR/kit/START-HERE.txt" <<'HELP'
ENDEAVOUROS USB WITH PRELOADED MACBOOKPRO5,1 EXPERIMENTAL KERNEL

This custom USB BOOTS THE ORIGINAL ENDEAVOUROS LIVE KERNEL.
The verified experimental kernel, headers and source are ALREADY ON THE
USB in /MBP51/dist. It is not installed by Calamares automatically.
The proprietary Broadcom wl binary must be built locally later.

1. Rufus (Windows) -> this custom ISO -> DD Image mode -> USB.
2. Boot MacBook with Option/Alt -> EFI Boot -> standard live environment.
3. Calamares ONLINE -> LXQt -> GRUB -> unencrypted Btrfs -> erase ADATA SSD.
4. First boot stock EndeavourOS; add and verify linux-lts recovery kernel.
5. Mount the USB's ISO9660 partition on the INSTALLED system; copy the
   /MBP51 directory from it to ~/MBP51, then:
      cd ~/MBP51
      bash scripts/verify-artifacts.sh dist
      bash install/activate-endeavouros-kernel.sh --plan dist
      bash install/activate-endeavouros-kernel.sh --install dist
   Stock boot remains default. broadcom-wl-dkms source needs to be
   installed or already cached; this does not require kernel downloading.
6. Reboot and manually select experimental GRUB entry. Validate GPU,
   BCM4322 WLAN, ACPI S3 suspend/resume, thermals and battery life.

The pinned 7.4 DEVELOPMENT snapshot reports version 7.3.0 upstream.
Not physically boot-qualified. No proprietary wl.ko shipped in this ISO.
HELP
(cd "$OUTPUT_DIR/kit" && sha256sum dist/*.pkg.tar.zst > ISO-PACKAGES.sha256)
out="$OUTPUT_DIR/EndeavourOS_Titan-Nova-MBP51-2026.10.25.iso"
xorriso -indev "$ORIGINAL_ISO" -outdev "$out" \
  -map "$OUTPUT_DIR/kit" /MBP51 \
  -boot_image any replay -commit -end
xorriso -indev "$ORIGINAL_ISO" -report_el_torito plain -end > "$OUTPUT_DIR/tmp/boot-original.txt" 2>&1
xorriso -indev "$out" -report_el_torito plain -end > "$OUTPUT_DIR/tmp/boot-remix.txt" 2>&1
grep -Eqi 'EFI|UEFI' "$OUTPUT_DIR/tmp/boot-original.txt"
grep -Eqi 'EFI|UEFI' "$OUTPUT_DIR/tmp/boot-remix.txt"
grep -Eqi 'BIOS|El Torito' "$OUTPUT_DIR/tmp/boot-remix.txt"
xorriso -osirrox on -indev "$out" \
  -extract /MBP51/dist/kernelrelease.txt "$OUTPUT_DIR/tmp/extracted.txt" -end
cmp "$DIST_DIR/kernelrelease.txt" "$OUTPUT_DIR/tmp/extracted.txt"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$out")" > custom-iso.sha256)
printf 'Upstream: Titan Nova 2026.08.15, checksum verified\nKernel: %s\nDoes not switch the live boot kernel or auto-install custom kernel.\n' "$K" > "$OUTPUT_DIR/RELEASE-NOTES.txt"
echo "PASS: Custom Rufus-ready ISO carries verified kernel packages and EFI boot."
ls -lh "$out"