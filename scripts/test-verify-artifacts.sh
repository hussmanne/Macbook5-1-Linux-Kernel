#!/usr/bin/env bash
# No kernel compile needed: deterministic regression tests of artifact verification.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
source "$root/scripts/tier-profile.sh"
if [[ "$MBP51_TIER" == bore ]]; then
  source "$root/patches/bore.lock"
elif [[ "$MBP51_TIER" == lab ]]; then
  source "$root/patches/lab.lock"
fi
release="$MBP51_KERNEL_RELEASE"
version="${release//-/_}"
printf '%s\n' "$release" > "$temp/kernelrelease.txt"
printf 'source_commit=%s\nkernel_release=%s\nkernel_tier=%s\npkgbase=%s\n' \
  "$SOURCE_SHA" "$release" "$MBP51_TIER" "$MBP51_PKGBASE" > "$temp/build-manifest.txt"
echo 'CONFIG_CPU_MITIGATIONS=n' > "$temp/resolved.config"
if [[ "$MBP51_TIER" == bore ]]; then
  printf 'patchset=%s\npatch_sha256=%s\n' "$BORE_PATCH_REV" "$BORE_PATCH_SHA256" >> "$temp/build-manifest.txt"
  printf 'patchset=%s\npatch_sha256=%s\n' "$BORE_PATCH_REV" "$BORE_PATCH_SHA256" > "$temp/patch-manifest.txt"
  echo 'CONFIG_SCHED_BORE=y' >> "$temp/resolved.config"
elif [[ "$MBP51_TIER" == lab ]]; then
  printf 'patchset=%s\nprofile_kind=%s\n' "$LAB_PROFILE_REV" "$LAB_PROFILE_KIND" > "$temp/patch-manifest.txt"
  printf 'patchset=%s\nprofile_kind=%s\n' "$LAB_PROFILE_REV" "$LAB_PROFILE_KIND" >> "$temp/build-manifest.txt"
  printf 'CONFIG_HZ_250=y\nCONFIG_HZ=250\n' >> "$temp/resolved.config"
fi
printf 'dummy kernel\n' > "$temp/$MBP51_PKGBASE-$version-1-x86_64.pkg.tar.zst"
printf 'dummy headers\n' > "$temp/$MBP51_PKGBASE-headers-$version-1-x86_64.pkg.tar.zst"
(cd "$temp" && sha256sum -- *.pkg.tar.zst > packages.sha256)
bash "$root/scripts/verify-artifacts.sh" "$temp"
sed -i 's@linux-mbp51@/work/dist/linux-mbp51@' "$temp/packages.sha256"
if bash "$root/scripts/verify-artifacts.sh" "$temp"; then
  echo "ERROR: verifier accepted nonportable absolute checksum filenames" >&2
  exit 1
fi
echo "Artifact verifier regression test passed"
