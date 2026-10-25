#!/usr/bin/env bash
# Source this from other scripts. Legacy v2 remains the compatibility default.
# Only Daily is currently implemented; other tiers MUST fail closed.
_mb_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$_mb_root/source.lock"
MBP51_TIER=${MBP51_TIER:-legacy}
case "$MBP51_TIER" in
  legacy)
    MBP51_PKGBASE=linux-mbp51-extreme
    MBP51_WL_PKGNAME=mbp51-broadcom-wl
    ;;
  daily)
    KERNEL_LOCALVERSION="-mbp51-daily-g${SOURCE_SHA:0:8}-v1"
    MBP51_PKGBASE=linux-mbp51-daily
    MBP51_WL_PKGNAME=mbp51-broadcom-wl-daily
    ;;
  bore|lab)
    echo "Tier '$MBP51_TIER' is not available: no verified scheduler/voltage patchset" >&2
    return 2 2>/dev/null || exit 2
    ;;
  *)
    echo "Unknown MBP51_TIER: $MBP51_TIER" >&2
    return 2 2>/dev/null || exit 2
    ;;
esac
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ &&
   "$KERNEL_LOCALVERSION" == "-mbp51-extreme-g${SOURCE_SHA:0:8}-v2" && "$MBP51_TIER" == legacy ||
   "$KERNEL_LOCALVERSION" == "-mbp51-daily-g${SOURCE_SHA:0:8}-v1" && "$MBP51_TIER" == daily ]] || {
  echo "Invalid tier-specific kernel ABI" >&2
  return 2 2>/dev/null || exit 2
}
