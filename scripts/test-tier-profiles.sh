#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
for tier in legacy daily; do
  export MBP51_TIER="$tier"
  # Ensure source is reloaded as a new child shell rather than contaminated.
  bash -euc '
    source "$1/scripts/tier-profile.sh"
    case "$MBP51_TIER" in
      legacy) [[ "$MBP51_PKGBASE" == linux-mbp51-extreme &&
                 "$MBP51_WL_PKGNAME" == mbp51-broadcom-wl &&
                 "$KERNEL_LOCALVERSION" == -mbp51-extreme-g*-v2 ]] ;;
      daily) [[ "$MBP51_PKGBASE" == linux-mbp51-daily &&
                "$MBP51_WL_PKGNAME" == mbp51-broadcom-wl-daily &&
                "$KERNEL_LOCALVERSION" == -mbp51-daily-g*-v1 ]] ;;
    esac
  ' _ "$root"
  bash "$root/scripts/test-verify-artifacts.sh"
done
for bad in bore lab typo; do
  if MBP51_TIER="$bad" bash -c 'source "$1/scripts/tier-profile.sh"' _ "$root"; then
    echo "ERROR: Unimplemented/unknown tier was accepted: $bad" >&2; exit 1
  fi
done
echo 'Tier profile and artifact isolation checks passed.'
