#!/usr/bin/env bash
# Apply only the immutable patchset selected by MBP51_TIER.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
[[ $# -ge 1 && $# -le 2 && -d "$1" ]] || {
  echo "Usage: $0 /path/to/extracted/linux [manifest]" >&2; exit 2;
}
source "$root/scripts/tier-profile.sh"
src=$1
manifest=${2:-"$src/mbp51-patch-manifest.txt"}

if [[ "$MBP51_TIER" != bore ]]; then
  if [[ "$MBP51_TIER" == lab ]]; then
    source "$root/patches/lab.lock"
    [[ "$SOURCE_SHA" == "$LAB_TARGET_SOURCE_SHA" ]] || {
      echo "Lab profile targets $LAB_TARGET_SOURCE_SHA, source.lock is $SOURCE_SHA" >&2; exit 1;
    }
    printf 'patchset=%s\nprofile_kind=%s\nkernel_tier=lab\nsource_commit=%s\n' \
      "$LAB_PROFILE_REV" "$LAB_PROFILE_KIND" "$SOURCE_SHA" > "$manifest"
  else
    printf 'patchset=none\nkernel_tier=%s\n' "$MBP51_TIER" > "$manifest"
  fi
  exit 0
fi

source "$root/patches/bore.lock"
patch="$root/$BORE_PATCH_FILE"
[[ "$SOURCE_SHA" == "$BORE_TARGET_SOURCE_SHA" ]] || {
  echo "BORE patch targets $BORE_TARGET_SOURCE_SHA, source.lock is $SOURCE_SHA" >&2; exit 1;
}
[[ -s "$patch" ]] || { echo "Missing BORE patch: $patch" >&2; exit 1; }
actual_sha=$(sha256sum "$patch" | cut -d' ' -f1)
[[ "$actual_sha" == "$BORE_PATCH_SHA256" ]] || {
  echo "BORE patch hash mismatch: $actual_sha" >&2; exit 1;
}

(cd "$src" && git apply --check --whitespace=error "$patch")
(cd "$src" && git apply --whitespace=error "$patch")
printf 'kernel_tier=bore\npatchset=%s\npatch_file=%s\npatch_sha256=%s\nsource_commit=%s\n' \
  "$BORE_PATCH_REV" "$BORE_PATCH_FILE" "$actual_sha" "$SOURCE_SHA" > "$manifest"
echo "Applied verified BORE patch $BORE_PATCH_REV to $SOURCE_SHA"
