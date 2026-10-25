#!/usr/bin/env bash
# Fast PR gate: validate resolved pinned upstream .config without compiling the kernel.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/source.lock"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid source SHA" >&2; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fL --retry 5 --retry-all-errors \
  "https://codeload.github.com/torvalds/linux/tar.gz/$SOURCE_SHA" -o "$tmp/linux.tar.gz"
sha256sum "$tmp/linux.tar.gz"
tar -xzf "$tmp/linux.tar.gz" -C "$tmp"
src="$tmp/linux-$SOURCE_SHA"
test -f "$src/Makefile"
make -C "$src" x86_64_defconfig
bash "$root/scripts/configure.sh" "$src"
make -C "$src" olddefconfig
bash "$root/scripts/audit-config.sh" "$src/.config"
echo "Pinned upstream Kconfig check passed: $SOURCE_SHA"
