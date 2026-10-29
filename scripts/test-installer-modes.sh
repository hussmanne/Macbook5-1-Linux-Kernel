#!/usr/bin/env bash
# Deterministic regression tests for the tier installer's mode handling.
# No kernel compile, no root, no Arch host, no disk changes: every call either
# stops in --plan or is expected to refuse before touching the system.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok  $*"; }

# Build a synthetic, structurally valid artifact directory for one tier.
make_artifacts() {
  local tier=$1 out=$2
  mkdir -p "$out"
  MBP51_TIER="$tier" bash -c '
    source "$1/scripts/tier-profile.sh"
    out=$2
    rel=$MBP51_KERNEL_RELEASE
    ver=${rel//-/_}
    printf "%s\n" "$rel" > "$out/kernelrelease.txt"
    {
      printf "source_commit=%s\n" "$SOURCE_SHA"
      printf "kernel_release=%s\n" "$rel"
      printf "kernel_tier=%s\n" "$MBP51_TIER"
      printf "pkgbase=%s\n" "$MBP51_PKGBASE"
      case "$MBP51_TIER" in
        bore) printf "patchset=%s\npatch_sha256=%s\n" "$BORE_PATCH_REV" "$BORE_PATCH_SHA256" ;;
        lab)  printf "patchset=%s\nprofile_kind=%s\n" "$LAB_PROFILE_REV" "$LAB_PROFILE_KIND" ;;
      esac
    } > "$out/build-manifest.txt"
    printf "CONFIG_CPU_MITIGATIONS=n\n" > "$out/resolved.config"
    case "$MBP51_TIER" in
      bore) printf "CONFIG_SCHED_BORE=y\n" >> "$out/resolved.config"
             printf "patchset=%s\npatch_sha256=%s\n" "$BORE_PATCH_REV" "$BORE_PATCH_SHA256" > "$out/patch-manifest.txt" ;;
      lab)  printf "CONFIG_HZ_250=y\nCONFIG_HZ=250\n" >> "$out/resolved.config"
             printf "patchset=%s\nprofile_kind=%s\n" "$LAB_PROFILE_REV" "$LAB_PROFILE_KIND" > "$out/patch-manifest.txt" ;;
    esac
    : > "$out/$MBP51_PKGBASE-$ver-1-x86_64.pkg.tar.zst"
    : > "$out/$MBP51_PKGBASE-headers-$ver-1-x86_64.pkg.tar.zst"
    ( cd "$out" && sha256sum -- *.pkg.tar.zst > packages.sha256 )
  ' _ "$root" "$out"
}

run_tier() {
  local tier=$1 dir=$2 installer=$3
  echo "== $tier =="

  out=$(MBP51_TIER="$tier" bash "$installer" --plan "$dir" 2>&1) ||
    fail "$tier --plan exited non-zero: $out"
  grep -q 'Read-only package verification succeeded' <<<"$out" ||
    fail "$tier --plan did not report success"
  grep -q "Verified portable package artifacts for" <<<"$out" ||
    fail "$tier --plan did not verify artifacts"
  pass "--plan verifies and stops"

  out=$(MBP51_TIER="$tier" bash "$installer" --plan "$dir" --no-wifi 2>&1) ||
    fail "$tier --plan --no-wifi exited non-zero"
  grep -q 'Mode: no Wi-Fi' <<<"$out" || fail "$tier --no-wifi not announced"
  pass "--no-wifi is announced next to --plan"

  out=$(MBP51_TIER="$tier" bash "$installer" --no-wifi --plan "$dir" 2>&1) ||
    fail "$tier flag order (--no-wifi before --plan) exited non-zero"
  grep -q 'Mode: no Wi-Fi' <<<"$out" || fail "$tier flags are order-sensitive"
  pass "flags are order-insensitive"

  if MBP51_TIER="$tier" bash "$installer" --wifi-only --no-wifi "$dir" >/dev/null 2>&1; then
    fail "$tier accepted contradictory --wifi-only --no-wifi"
  fi
  pass "contradictory flags are refused"

  if MBP51_TIER="$tier" bash "$installer" --bogus >/dev/null 2>&1; then
    fail "$tier accepted an unknown option"
  fi
  pass "unknown options are refused"

  # --install must refuse on a non-Arch host before any mutation. This is the
  # guard that keeps a mis-invoked installer from touching a non-target box.
  if [[ ! -f /etc/arch-release ]]; then
    out=$(MBP51_TIER="$tier" bash "$installer" --install "$dir" 2>&1 || true)
    grep -q 'Requires Arch/EndeavourOS' <<<"$out" ||
      fail "$tier --install did not stop at the Arch guard: $out"
    pass "--install refuses on a non-Arch host"
  fi
}

# Static structure: the GRUB entry must be derived from GRUB itself, never from
# a hand-assembled "$subvol/boot/..." path.
for script in install/activate-daily-kernel.sh install/activate-custom-kernel.sh; do
  grep -q 'grub-mkrelpath' "$root/$script" || fail "$script does not use grub-mkrelpath"
  grep -q 'grub-probe' "$root/$script" || fail "$script does not use grub-probe"
  if grep -qE 'linux \\$subvol/boot/' "$root/$script"; then
    fail "$script still hand-assembles the boot path from the subvolume"
  fi
done
pass "both installers resolve boot paths with grub-probe/grub-mkrelpath"

grep -q -- '--no-wifi' "$root/scripts/postboot-check.sh" ||
  fail "postboot-check.sh does not accept --no-wifi"
pass "postboot-check.sh accepts --no-wifi"

for tier in daily bore lab; do
  make_artifacts "$tier" "$temp/$tier"
done
run_tier daily "$temp/daily" "$root/install/activate-daily-kernel.sh"
run_tier bore  "$temp/bore"  "$root/install/activate-bore-kernel.sh"
run_tier lab   "$temp/lab"   "$root/install/activate-lab-kernel.sh"

echo "Installer mode regression tests passed."
