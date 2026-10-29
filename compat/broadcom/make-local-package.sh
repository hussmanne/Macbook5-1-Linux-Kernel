#!/usr/bin/env bash
# Build a pacman-installable, source-specific Broadcom module LOCALLY.
# Uses Arch's installed proprietary driver; do not redistribute binary module.
# This does not install, load, or overwrite any running stock-kernel module.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$root/scripts/tier-profile.sh"
release=${1:-}
[[ "$EUID" -ne 0 ]] || { echo "Run as a regular user, never root." >&2; exit 2; }
[[ "$release" == "$MBP51_KERNEL_RELEASE" ]] || {
  echo "Expected release $MBP51_KERNEL_RELEASE" >&2; exit 2;
}
[[ $# -le 2 ]] || { echo "Usage: $0 KERNELRELEASE [EXISTING_WL_KO]" >&2; exit 2; }
for tool in makepkg bsdtar modinfo sha256sum; do
  command -v "$tool" >/dev/null || { echo "Missing command: $tool" >&2; exit 2; }
done
out="$root/.work/broadcom/$release"
if [[ $# -eq 1 ]]; then
  bash "$root/compat/broadcom/build-on-device.sh" "$release"
  module="$out/wl.ko"
else
  module="$2"   # CI-compiled wl.ko; already tested against exact headers.
fi
[[ -s "$module" ]] || { echo "No valid built wl.ko: $module" >&2; exit 1; }
vermagic=$(modinfo -F vermagic "$module")
[[ "$vermagic" == "$release "* ]] || {
  echo "Wrong module vermagic: $vermagic" >&2; exit 1;
}
pkgver=${release//-/_}
stage="$out/package"
mkdir -p "$stage"
cp "$module" "$stage/wl.ko"
module_hash=$(sha256sum "$stage/wl.ko" | cut -d' ' -f1)
cat > "$stage/PKGBUILD" <<'PKGBUILD'
# This build is generated locally; its wl.ko contains proprietary Broadcom code.
pkgname=@@WL_PKGNAME@@
pkgver=@@VERSION@@
pkgrel=1
pkgdesc='Locally built BCM4322 wl driver for pinned MacBookPro5,1 kernel'
arch=('x86_64')
url='https://github.com/hussmanne/Macbook5-1-Linux-Kernel'
license=('custom')
depends=('@@KERNEL_PKGBASE@@' 'kmod')
source=('wl.ko')
sha256sums=('@@SHA256@@')
options=('!strip' '!debug')
package() {
  install -Dm644 "$srcdir/wl.ko" "$pkgdir/usr/lib/modules/@@RELEASE@@/updates/mbp51/wl.ko"
}
PKGBUILD
sed -i -e "s/@@WL_PKGNAME@@/$MBP51_WL_PKGNAME/" \
       -e "s/@@KERNEL_PKGBASE@@/$MBP51_PKGBASE/" \
       -e "s/@@VERSION@@/$pkgver/" \
       -e "s/@@SHA256@@/$module_hash/" \
       -e "s/@@RELEASE@@/$release/" "$stage/PKGBUILD"
(cd "$stage" && makepkg --noconfirm --force --nodeps --cleanbuild)
shopt -s nullglob
packages=("$stage"/"$MBP51_WL_PKGNAME"-"$pkgver"-*-x86_64.pkg.tar.zst)
[[ ${#packages[@]} -eq 1 && -s "${packages[0]}" ]] || {
  echo "Missing locally built module package" >&2; exit 1;
}
bsdtar -tf "${packages[0]}" | grep -Fx \
  "usr/lib/modules/$release/updates/mbp51/wl.ko" >/dev/null || {
    echo "Packaged wl.ko did not land in expected custom kernel module path" >&2; exit 1;
  }
(cd "$stage" && sha256sum "$(basename "${packages[0]}")" > module-package.sha256)
echo "PASS: local pacman package ${packages[0]}"
echo "No kernel, stock driver, bootloader or loaded module has been changed."
echo "Install only after following docs/INSTALL.md and verifying the exact headers."
