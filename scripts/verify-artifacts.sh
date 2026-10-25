#!/usr/bin/env bash
# Portable, host-side verification for the downloadable kernel artifact directory.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
dist=${1:-"$root/dist"}
[[ -d "$dist" ]] || { echo "Missing artifact directory: $dist" >&2; exit 1; }
for f in kernelrelease.txt build-manifest.txt resolved.config packages.sha256; do
  [[ -s "$dist/$f" ]] || { echo "Missing or empty artifact: $f" >&2; exit 1; }
done
release=$(< "$dist/kernelrelease.txt")
source "$root/scripts/tier-profile.sh"
[[ "$release" =~ ^[0-9][0-9A-Za-z._+-]*$ &&
   "$release" == *"$KERNEL_LOCALVERSION" ]] || {
  echo "Unexpected kernel release: $release" >&2; exit 1;
}
grep -Fxq "kernel_release=$release" "$dist/build-manifest.txt" || {
  echo "Kernel release disagrees with build manifest" >&2; exit 1;
}
grep -Fxq "source_commit=$SOURCE_SHA" "$dist/build-manifest.txt" || {
  echo "Pinned upstream SHA disagrees with build manifest" >&2; exit 1;
}
if [[ "$MBP51_TIER" != legacy ]]; then
  grep -Fxq "kernel_tier=$MBP51_TIER" "$dist/build-manifest.txt" &&
    grep -Fxq "pkgbase=$MBP51_PKGBASE" "$dist/build-manifest.txt" || {
      echo "Tier/package identity mismatch" >&2; exit 1;
    }
fi
shopt -s nullglob
kernel=("$dist"/"$MBP51_PKGBASE"-[0-9]*-x86_64.pkg.tar.zst)
headers=("$dist"/"$MBP51_PKGBASE"-headers-[0-9]*-x86_64.pkg.tar.zst)
all=("$dist"/*.pkg.tar.zst)
[[ ${#kernel[@]} -eq 1 && ${#headers[@]} -eq 1 && ${#all[@]} -eq 2 ]] || {
  echo "Expected exactly one kernel and one headers package" >&2; exit 1;
}
packaged_version=${release//-/_}
for pkg in "${kernel[0]}" "${headers[0]}"; do
  [[ "$(basename "$pkg")" == *-"$packaged_version"-*-x86_64.pkg.tar.zst ]] || {
    echo "Package filename disagrees with release: $pkg" >&2; exit 1;
  }
done
# Verify only portable basenames are present. Reject absolute Docker paths and traversal.
line_count=0
declare -A listed=()
while read -r hash filename rest; do
  [[ "$hash" =~ ^[0-9a-f]{64}$ && "$filename" =~ ^[A-Za-z0-9._+-]+\.pkg\.tar\.zst$ && -z "${rest:-}" ]] || {
    echo "Invalid or nonportable packages.sha256 entry: $filename" >&2; exit 1;
  }
  [[ -z "${listed[$filename]+set}" ]] || { echo "Duplicate checksum entry: $filename" >&2; exit 1; }
  listed["$filename"]=1
  ((line_count+=1))
done < "$dist/packages.sha256"
[[ $line_count -eq 2 ]] || { echo "Expected two checksum entries" >&2; exit 1; }
for pkg in "${kernel[0]}" "${headers[0]}"; do
  [[ -n "${listed[$(basename "$pkg")]+set}" ]] || { echo "Checksum entry missing: $pkg" >&2; exit 1; }
done
(cd "$dist" && sha256sum -c packages.sha256)
echo "Verified portable package artifacts for $release"
