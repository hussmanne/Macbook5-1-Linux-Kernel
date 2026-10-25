#!/usr/bin/env bash
# Read-only compatibility test on an Arch Linux CI runner; never loads wl into
# the host kernel or modifies the user's MacBook. Requires dkms + Arch wl sources.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
dist=${1:-"$root/dist"}
report=${2:-"$root/report"}
mkdir -p "$report"
release=""
wl_ver=""
on_exit() {
  local result=$?
  if [[ -n "$wl_ver" && -d /var/lib/dkms/broadcom-wl/"$wl_ver" ]]; then
    find /var/lib/dkms/broadcom-wl/"$wl_ver" -type f -name make.log -print \
      -exec cp -f '{}' "$report/wl-make.log" \; || :
  fi
  dkms status > "$report/dkms-status.txt" 2>&1 || :
  printf 'exit_code=%s\nkernel_release=%s\nwl_version=%s\n' \
    "$result" "$release" "$wl_ver" > "$report/result.txt"
  exit "$result"
}
trap on_exit EXIT

bash "$root/scripts/verify-artifacts.sh" "$dist"
release=$(< "$dist/kernelrelease.txt")
headers=("$dist"/linux-mbp51-extreme-headers-[0-9]*-x86_64.pkg.tar.zst)
[[ ${#headers[@]} -eq 1 && -f "${headers[0]}" ]] || {
  echo "Expected exactly one headers package" >&2; exit 1;
}

# Install only the matching headers into this ephemeral Arch container.
# The tested wl source comes from Arch Extra, not an untracked third-party fork.
pacman -U --noconfirm "${headers[0]}"
test -s "/usr/lib/modules/$release/build/Module.symvers"
test -s "/usr/lib/modules/$release/build/include/config/auto.conf"

shopt -s nullglob
sources=(/usr/src/broadcom-wl-*)
[[ ${#sources[@]} -eq 1 && -d "${sources[0]}" ]] || {
  echo "Expected one Arch broadcom-wl source directory" >&2; exit 1;
}
wl_ver=${sources[0]##*/broadcom-wl-}
printf 'kernel_release=%s\nwl_version=%s\narch_package=%s\n' \
  "$release" "$wl_ver" "$(pacman -Q broadcom-wl-dkms)" > "$report/source-versions.txt"

# pacman may already register DKMS source. Register it if missing.
python3 "$root/compat/broadcom/patch-broadcom-wl.py" "${sources[0]}" "$release" "$report"

if [[ ! -L "/var/lib/dkms/broadcom-wl/$wl_ver/source" ]]; then
  dkms add -m broadcom-wl -v "$wl_ver"
fi

# Compile for the custom *non-running* kernel. No modprobe, blacklist changes,
# or fake host-kernel symlinks; this is a build/link compatibility check only.
dkms build -m broadcom-wl -v "$wl_ver" -k "$release" 2>&1 | tee "$report/wl-build.log"
mapfile -t modules < <(find "/var/lib/dkms/broadcom-wl/$wl_ver" \
  -type f -name 'wl.ko*')
[[ ${#modules[@]} -ge 1 ]] || { echo "DKMS finished but wl.ko missing" >&2; exit 1; }
modinfo -F vermagic "${modules[0]}" | tee "$report/vermagic.txt"
grep -Fq "$release" "$report/vermagic.txt" || {
  echo "Built wl.ko vermagic doesn't match custom kernel" >&2; exit 1;
}
echo "PASS: Broadcom wl DKMS builds for $release ($wl_ver)"

# Prove a pacman-installable module can be generated without distributing the
# proprietary driver in a public CI artifact. Only log package name/hash.
useradd -m -u 1000 mbp51pack
mkdir -p "$root/.work"
chown -R mbp51pack:mbp51pack "$root/.work"
runuser -u mbp51pack -- bash "$root/compat/broadcom/make-local-package.sh" "$release" "${modules[0]}"
pkg="$root/.work/broadcom/$release/package/mbp51-broadcom-wl-${release//-/_}-1-x86_64.pkg.tar.zst"
[[ -s "$pkg" ]] || { echo "Local module package absent" >&2; exit 1; }
pacman -Qip "$pkg" > "$report/module-package-metadata.txt"
printf '\nPackage SHA-256: ' >> "$report/module-package-metadata.txt"
sha256sum "$pkg" | cut -d' ' -f1 >> "$report/module-package-metadata.txt"
echo "PASS: local pacman package created and verified; no binary redistributed"
