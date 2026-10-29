#!/usr/bin/env bash
# Fast PR gate: validate resolved pinned upstream .config without compiling the kernel.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/source.lock"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid source SHA" >&2; exit 2; }
[[ "${SOURCE_ARCHIVE_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid pinned archive SHA256" >&2; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cache_dir=${MBP51_CACHE_DIR:-"$tmp"}
mkdir -p "$cache_dir"
archive="$cache_dir/linux-$SOURCE_SHA.tar.gz"
# Validate all cached content against a pinned digest: public PR caches must
# never be trusted without hash verification.
if [[ ! -s "$archive" ]] || ! printf '%s  %s\n' "$SOURCE_ARCHIVE_SHA256" "$archive" | sha256sum -c -; then
  rm -f "$archive"
  curl -fL --retry 8 --retry-delay 12 --retry-max-time 360 --retry-all-errors \
    "https://codeload.github.com/torvalds/linux/tar.gz/$SOURCE_SHA" -o "$archive.tmp"
  printf '%s  %s\n' "$SOURCE_ARCHIVE_SHA256" "$archive.tmp" | sha256sum -c -
  mv "$archive.tmp" "$archive"
fi
tar -xzf "$archive" -C "$tmp"
src="$tmp/linux-$SOURCE_SHA"
test -f "$src/Makefile"
bash "$root/scripts/apply-tier-patches.sh" "$src" "$tmp/patch-manifest.txt"
make -C "$src" x86_64_defconfig
bash "$root/scripts/configure.sh" "$src"
make -C "$src" olddefconfig
bash "$root/scripts/audit-config.sh" "$src/.config"
echo "Pinned upstream Kconfig check passed: $SOURCE_SHA"
