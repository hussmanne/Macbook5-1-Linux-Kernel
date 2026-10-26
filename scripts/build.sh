#!/usr/bin/env bash
# Run as unprivileged Arch Linux user (on GitHub Actions build container).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
source "$root/scripts/tier-profile.sh"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid source SHA" >&2; exit 2; }
work="$root/.work"
out="$root/dist"
[[ "$MBP51_TIER" != legacy ]] && out="$root/dist/$MBP51_TIER"
mkdir -p "$work" "$out"
archive="$work/linux-$SOURCE_SHA.tar.gz"
cached="$root/.cache/kconfig/linux-$SOURCE_SHA.tar.gz"
# PR/main static validation has already independently fetched and SHA-verified
# this source. Reuse the same immutable blob to avoid GitHub codeload rate limits.
if [[ -s "$cached" ]]; then
  if printf '%s  %s\n' "$SOURCE_ARCHIVE_SHA256" "$cached" | sha256sum -c -; then
    echo "Restoring hash-verified kernel source from Actions cache."
    cp -f "$cached" "$archive"
  else
    echo "Ignoring cached archive with mismatching SHA-256." >&2
  fi
fi
# Always validate the work archive before unpacking, including preexisting files.
if [[ ! -s "$archive" ]] || ! printf '%s  %s\n' "$SOURCE_ARCHIVE_SHA256" "$archive" | sha256sum -c -; then
  rm -f "$archive" "$archive.tmp"
  echo "No valid cached archive. Downloading pinned upstream SHA with backoff."
  curl -fL --retry 8 --retry-delay 12 --retry-max-time 600 --retry-all-errors \
    "https://codeload.github.com/torvalds/linux/tar.gz/$SOURCE_SHA" -o "$archive.tmp"
  printf '%s  %s\n' "$SOURCE_ARCHIVE_SHA256" "$archive.tmp" | sha256sum -c -
  mv "$archive.tmp" "$archive"
fi
archive_sha256="$SOURCE_ARCHIVE_SHA256"
printf '%s  %s\n' "$archive_sha256" "$(basename "$archive")" > "$out/source-archive.sha256"
src="$work/linux-$SOURCE_SHA"
rm -rf "$src"
tar -xzf "$archive" -C "$work"
[[ -f "$src/Makefile" ]] || exit 1
patch_manifest="$out/patch-manifest.txt"
bash "$root/scripts/apply-tier-patches.sh" "$src" "$patch_manifest"
cd "$src"
make x86_64_defconfig
bash "$root/scripts/configure.sh" "$src"
make olddefconfig
bash "$root/scripts/audit-config.sh" "$src/.config"
cp .config "$out/resolved.config"

# Use upstream's maintained Arch packaging, including correct DKMS header tree.
export PACMAN_PKGBASE="$MBP51_PKGBASE"
export PACMAN_EXTRAPACKAGES=headers
export MAKEPKGOPTS="--nodeps --noconfirm"
# Scheduler tuning only; -mtune=core2 does NOT enable newer CPU instructions
# or change the x86-64 baseline. Never use -march=native on GitHub runners.
export KCFLAGS="-mtune=core2"
make -j"$(nproc)" pacman-pkg
while IFS= read -r -d '' pkg; do cp "$pkg" "$out/"; done \
  < <(find "$src" -name '*.pkg.tar.zst' -type f -print0)
count=$(find "$out" -maxdepth 1 -name '*.pkg.tar.zst' -type f | wc -l)
[[ "$count" -eq 2 ]] || { echo "Expected kernel and headers; got $count packages" >&2; exit 1; }

# The initial pre-build make kernelrelease may omit LOCALVERSION. Use the
# generated release the packaging step actually installed its modules under.
[[ -s include/config/kernel.release ]] || { echo "Missing built kernel release" >&2; exit 1; }
release=$(< include/config/kernel.release)
[[ "$release" == *"$KERNEL_LOCALVERSION" ]] || { echo "Unexpected built release: $release" >&2; exit 1; }
printf '%s\n' "$release" > "$out/kernelrelease.txt"
patch_sha256=$(awk -F= '$1 == "patch_sha256" { print $2; exit }' "$patch_manifest")
printf 'source_commit=%s\nkernel_release=%s\nsource_archive_sha256=%s\n' \
  "$SOURCE_SHA" "$release" "$archive_sha256" > "$out/build-manifest.txt"
printf 'kernel_tuning_flags=%s\nkernel_tier=%s\npkgbase=%s\npatchset=%s\npatch_sha256=%s\n' \
  "$KCFLAGS" "$MBP51_TIER" "$MBP51_PKGBASE" "$MBP51_PATCHSET" "${patch_sha256:-none}" >> "$out/build-manifest.txt"
gcc --version | head -n 1 >> "$out/build-manifest.txt"

# Ensure that headers and bootable image use exactly the same module ABI path.
kernel_pkg=("$out"/"$MBP51_PKGBASE"-[0-9]*-x86_64.pkg.tar.zst)
headers_pkg=("$out"/"$MBP51_PKGBASE"-headers-[0-9]*-x86_64.pkg.tar.zst)
[[ "${#kernel_pkg[@]}" -eq 1 && -f "${kernel_pkg[0]}" ]] || { echo "Wrong kernel package count" >&2; exit 1; }
[[ "${#headers_pkg[@]}" -eq 1 && -f "${headers_pkg[0]}" ]] || { echo "Wrong headers package count" >&2; exit 1; }
bsdtar -tf "${kernel_pkg[0]}" | grep -Fx "usr/lib/modules/$release/vmlinuz" >/dev/null || \
  { echo "Kernel image missing from expected release path" >&2; exit 1; }
bsdtar -tf "${headers_pkg[0]}" | grep -Fx "usr/lib/modules/$release/build/.config" >/dev/null || \
  { echo "Headers config missing from expected release path" >&2; exit 1; }

# Hash basenames only so hashes verify from any extracted artifact directory.
(cd "$out" && sha256sum -- *.pkg.tar.zst > packages.sha256)
tar -czf "$out/runtime-config.tar.gz" -C "$root" runtime
bash "$root/scripts/verify-artifacts.sh" "$out"
echo "Build and package verification completed: $release"
