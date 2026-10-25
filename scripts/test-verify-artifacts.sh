#!/usr/bin/env bash
# No kernel compile needed: deterministic regression tests of artifact verification.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
source "$root/scripts/tier-profile.sh"
release="7.3.0$KERNEL_LOCALVERSION"
version="${release//-/_}"
printf '%s\n' "$release" > "$temp/kernelrelease.txt"
printf 'source_commit=%s\nkernel_release=%s\nkernel_tier=%s\npkgbase=%s\n' \
  "$SOURCE_SHA" "$release" "$MBP51_TIER" "$MBP51_PKGBASE" > "$temp/build-manifest.txt"
echo 'CONFIG_CPU_MITIGATIONS=n' > "$temp/resolved.config"
printf 'dummy kernel\n' > "$temp/$MBP51_PKGBASE-$version-1-x86_64.pkg.tar.zst"
printf 'dummy headers\n' > "$temp/$MBP51_PKGBASE-headers-$version-1-x86_64.pkg.tar.zst"
(cd "$temp" && sha256sum -- *.pkg.tar.zst > packages.sha256)
bash "$root/scripts/verify-artifacts.sh" "$temp"
sed -i 's@  linux-@  /work/dist/linux-@' "$temp/packages.sha256"
if bash "$root/scripts/verify-artifacts.sh" "$temp"; then
  echo "ERROR: verifier accepted nonportable absolute checksum filenames" >&2
  exit 1
fi
echo "Artifact verifier regression test passed"
