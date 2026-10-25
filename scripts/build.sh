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
sha256sum "$archive" > "$out/source-archive.sha256"
tar -xzf "$archive" -C "$work"
src="$work/linux-$SOURCE_SHA"
[[ -f "$src/Makefile" ]] || exit 1
cd "$src"
make x86_64_defconfig
bash "$root/scripts/configure.sh" "$src"
make olddefconfig
bash "$root/scripts/audit-config.sh" "$src/.config"
release=$(make -s kernelrelease)
printf '%s\n' "$release" > "$out/kernelrelease.txt"
cp .config "$out/resolved.config"
printf 'source_commit=%s\nkernel_release=%s\n' "$SOURCE_SHA" "$release" > "$out/build-manifest.txt"
gcc --version | head -n 1 >> "$out/build-manifest.txt"

# Use upstream's maintained Arch packaging, including correct DKMS header tree.
export PACMAN_PKGBASE=linux-mbp51-extreme
export PACMAN_EXTRAPACKAGES=headers
export MAKEPKGOPTS="--nodeps --noconfirm"
make -j"$(nproc)" pacman-pkg
while IFS= read -r -d '' pkg; do cp "$pkg" "$out/"; done \
  < <(find "$src" -name '*.pkg.tar.zst' -type f -print0)
count=$(find "$out" -maxdepth 1 -name '*.pkg.tar.zst' -type f | wc -l)
[[ "$count" -eq 2 ]] || { echo "Expected kernel and headers; got $count packages" >&2; exit 1; }
sha256sum "$out"/*.pkg.tar.zst > "$out/packages.sha256"
tar -czf "$out/runtime-config.tar.gz" -C "$root" runtime
echo "Build completed: $release"
