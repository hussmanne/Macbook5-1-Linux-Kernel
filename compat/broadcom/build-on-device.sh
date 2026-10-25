#!/usr/bin/env bash
# Build (but deliberately do NOT install or load) the patched Broadcom wl
# module for the custom MacBookPro5,1 kernel. Never edits the Arch-maintained
# /usr/src driver or any existing stock-kernel module.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
release=${1:-}
source "$root/scripts/tier-profile.sh"
if [[ $# -ne 1 || "$release" != "7.3.0$KERNEL_LOCALVERSION" ]]; then
  echo "Usage: bash compat/broadcom/build-on-device.sh KERNELRELEASE" >&2
  echo "Expected: bash compat/broadcom/build-on-device.sh 7.3.0$KERNEL_LOCALVERSION" >&2
  exit 2
fi
if [[ "$EUID" -eq 0 ]]; then
  echo "Compile as a regular user, not as root. Only install manually after review." >&2
  exit 2
fi
for tool in python3 make modinfo sha256sum cp; do
  command -v "$tool" >/dev/null || { echo "Missing command: $tool" >&2; exit 2; }
done
headers="/usr/lib/modules/$release/build"
[[ -s "$headers/Module.symvers" && -s "$headers/include/config/auto.conf" ]] || {
  echo "Matching custom kernel headers not installed: $headers" >&2; exit 2;
}
shopt -s nullglob
sources=(/usr/src/broadcom-wl-*)
[[ ${#sources[@]} -eq 1 && -d "${sources[0]}" ]] || {
  echo "Expected exactly one Arch broadcom-wl-dkms source directory." >&2; exit 2;
}
ver=${sources[0]##*/broadcom-wl-}
if [[ "$ver" != 6.30.223.271 ]]; then
  echo "Broadcom version changed ($ver); compatibility patch needs review." >&2
  exit 2
fi
if [[ ! -r "${sources[0]}/dkms.conf" ]]; then
  echo "Installed source missing DKMS definition; refusing to proceed." >&2; exit 2;
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/mbp51-wl.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/source" "$tmp/report"
cp -a "${sources[0]}/." "$tmp/source/"
python3 "$root/compat/broadcom/patch-broadcom-wl.py" "$tmp/source" "$release" "$tmp/report"

# Use the exact external module build command that the CI DKMS test invokes,
# but write into the private scratch tree rather than Arch's package-managed
# source or the live kernel's module directory.
make -j"$(nproc)" -C "$headers" "M=$tmp/source" "KERNELRELEASE=$release" \
  2>&1 | tee "$tmp/report/build.log"
test -s "$tmp/source/wl.ko" || {
  echo "Expected wl.ko was not produced" >&2; exit 1;
}
vermagic=$(modinfo -F vermagic "$tmp/source/wl.ko")
[[ "$vermagic" == "$release "* ]] || {
  echo "Built wl.ko has wrong vermagic: $vermagic" >&2; exit 1;
}

# Save the proprietary module only on this machine, never to public CI
# artifacts or the repository. The script does not install or load the module.
out="$root/.work/broadcom/$release"
mkdir -p "$out"
install -m 0644 "$tmp/source/wl.ko" "$out/wl.ko"
cp "$tmp/report/patch-manifest.txt" "$out/patch-manifest.txt"
cp "$tmp/report/build.log" "$out/build.log"
printf '%s\n' "$vermagic" > "$out/vermagic.txt"
(cd "$out" && sha256sum wl.ko > wl.ko.sha256)
echo "PASS: built $out/wl.ko for $release"
echo "No kernel modules or Arch driver source have been modified."
echo "Review docs/BROADCOM.md before any installation."
