#!/usr/bin/env bash
# Source this from other scripts. Legacy v2 remains the compatibility default.
# Daily, BORE, and the feature-preserving Extreme Lab profile are independently packaged.
#
# SINGLE SOURCE OF TRUTH for every kernel ABI string. Nothing else may
# hard-code a release: installers, the Broadcom patcher, CI verification and
# the ISO remaster all consume these variables. Bump MBP51_CONFIG_REV in
# source.lock when scripts/configure.sh changes, never here.
_mb_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$_mb_root/source.lock"
: "${KERNEL_VERSION:?source.lock must define KERNEL_VERSION}"
: "${MBP51_CONFIG_REV:?source.lock must define MBP51_CONFIG_REV}"
: "${MBP51_LEGACY_SUFFIX:?source.lock must define MBP51_LEGACY_SUFFIX}"
MBP51_TIER=${MBP51_TIER:-legacy}
case "$MBP51_TIER" in
  legacy)
    KERNEL_LOCALVERSION="${MBP51_LEGACY_SUFFIX}-${MBP51_CONFIG_REV}"
    MBP51_PKGBASE=linux-mbp51-extreme
    MBP51_WL_PKGNAME=mbp51-broadcom-wl
    MBP51_PATCHSET=none
    MBP51_BOOT_SUBDIR=legacy
    MBP51_GRUB_ID=mbp51-experimental-v2
    MBP51_GRUB_TITLE='MacBookPro5,1 experimental Linux'
    ;;
  daily)
    KERNEL_LOCALVERSION="-mbp51-daily-g${SOURCE_SHA:0:8}-v1-${MBP51_CONFIG_REV}"
    MBP51_PKGBASE=linux-mbp51-daily
    MBP51_WL_PKGNAME=mbp51-broadcom-wl-daily
    MBP51_PATCHSET=none
    MBP51_BOOT_SUBDIR=daily
    MBP51_GRUB_ID=mbp51-daily
    MBP51_GRUB_TITLE='MacBookPro5,1 Daily (upstream EEVDF)'
    ;;
  bore)
    source "$_mb_root/patches/bore.lock"
    KERNEL_LOCALVERSION="-mbp51-bore-g${SOURCE_SHA:0:8}-${BORE_PATCH_REV}-${MBP51_CONFIG_REV}"
    MBP51_PKGBASE=linux-mbp51-bore
    MBP51_WL_PKGNAME=mbp51-broadcom-wl-bore
    MBP51_PATCHSET="$BORE_PATCH_REV"
    MBP51_BOOT_SUBDIR=bore
    MBP51_GRUB_ID=mbp51-bore
    MBP51_GRUB_TITLE='MacBookPro5,1 BORE (default off)'
    ;;
  lab)
    source "$_mb_root/patches/lab.lock"
    KERNEL_LOCALVERSION="-mbp51-lab-g${SOURCE_SHA:0:8}-${LAB_PROFILE_REV}-${MBP51_CONFIG_REV}"
    MBP51_PKGBASE=linux-mbp51-extreme-lab
    MBP51_WL_PKGNAME=mbp51-broadcom-wl-lab
    MBP51_PATCHSET="$LAB_PROFILE_REV"
    MBP51_BOOT_SUBDIR=lab
    MBP51_GRUB_ID=mbp51-extreme-lab
    MBP51_GRUB_TITLE='MacBookPro5,1 Extreme Lab (250 Hz)'
    ;;
  *)
    echo "Unknown MBP51_TIER: $MBP51_TIER" >&2
    return 2 2>/dev/null || exit 2
    ;;
esac
# Full release string, e.g. 7.3.0-mbp51-daily-g21a7f44f-v1-c2
MBP51_KERNEL_RELEASE="${KERNEL_VERSION}${KERNEL_LOCALVERSION}"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid source SHA" >&2
  return 2 2>/dev/null || exit 2
}
[[ -n "$KERNEL_VERSION" && -n "$MBP51_CONFIG_REV" &&
   "$KERNEL_LOCALVERSION" == *"-${MBP51_CONFIG_REV}" ]] || {
  echo "Invalid tier-specific kernel ABI" >&2
  return 2 2>/dev/null || exit 2
}
case "$MBP51_TIER" in
  legacy) [[ "$KERNEL_LOCALVERSION" == "${MBP51_LEGACY_SUFFIX}-${MBP51_CONFIG_REV}" ]] ;;
  daily)  [[ "$KERNEL_LOCALVERSION" == "-mbp51-daily-g${SOURCE_SHA:0:8}-v1-${MBP51_CONFIG_REV}" ]] ;;
  bore)   [[ "$KERNEL_LOCALVERSION" == "-mbp51-bore-g${SOURCE_SHA:0:8}-${BORE_PATCH_REV}-${MBP51_CONFIG_REV}" ]] ;;
  lab)    [[ "$KERNEL_LOCALVERSION" == "-mbp51-lab-g${SOURCE_SHA:0:8}-${LAB_PROFILE_REV}-${MBP51_CONFIG_REV}" ]] ;;
  *) false ;;
esac || {
  echo "Invalid tier-specific kernel ABI" >&2
  return 2 2>/dev/null || exit 2
}
