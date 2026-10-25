#!/usr/bin/env bash
# Run as unprivileged Arch Linux user (on GitHub Actions build container).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
source source.lock
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid source SHA" >&2; exit 2; }
work="$root/.work"
out="$root/dist"
mkdir -p "$work" "$out"
archive="$work/linux-$SOURCE_SHA.tar.gz"
if [[ ! -s "$archive" ]]; then
  curl -fL --retry 5 --retry-all-errors \
    "https://codeload.github.com/torvalds/linux/tar.gz/$SOURCE_SHA" -o "$archive"
fi
# Use portable filenames in provenance manifests, not container-only absolute paths.
archive_sha256=$(sha256sum "$archive" | cut -d' ' -f1)
[[ "$archive_sha256" == "$SOURCE_ARCHIVE_SHA256" ]] || {
  echo "Upstream archive SHA256 differs from source.lock" >&2; exit 1;
}
printf '%s  %s\n' "$archive_sha256" "$(basename "$archive")" > "$out/source-archive.sha256"
tar -xzf "$archive" -C "$work"
src="$work/linux-$SOURCE_SHA"
[[ -f "$src/Makefile" ]] || exit 1
cd "$src"
make x86_64_defconfig
bash "$root/scripts/configure.sh" "$src"
make olddefconfig
bash "$root/scripts/audit-config.sh" "$src/.config"
cp .config "$out/resolved.config"

# Use upstream's maintained Arch packaging, including correct DKMS header tree.
export PACMAN_PKGBASE=linux-mbp51-extreme
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
[[ "$release" == *-mbp51-extreme ]] || { echo "Unexpected built release: $release" >&2; exit 1; }
printf '%s\n' "$release" > "$out/kernelrelease.txt"
printf 'source_commit=%s\nkernel_release=%s\nsource_archive_sha256=%s\n' \
  "$SOURCE_SHA" "$release" "$archive_sha256" > "$out/build-manifest.txt"
printf 'kernel_tuning_flags=%s\n' "$KCFLAGS" >> "$out/build-manifest.txt"
gcc --version | head -n 1 >> "$out/build-manifest.txt"

# Ensure that headers and bootable image use exactly the same module ABI path.
kernel_pkg=("$out"/linux-mbp51-extreme-[0-9]*-x86_64.pkg.tar.zst)
headers_pkg=("$out"/linux-mbp51-extreme-headers-[0-9]*-x86_64.pkg.tar.zst)
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
