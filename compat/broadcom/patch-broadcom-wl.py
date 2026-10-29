#!/usr/bin/env python3
"""Strict compatibility fixes for one pinned post-7.3 kernel source snapshot.

Changes only the ephemeral Arch DKMS driver source on GitHub Actions, never
the MacBook or kernel source. Reject unexpected driver/kernel source layouts.
"""
from pathlib import Path
import hashlib
import re
import sys

if len(sys.argv) != 4:
    sys.exit("Usage: patch-broadcom-wl.py SOURCE_DIR KERNEL_RELEASE REPORT_DIR")
src, release, report = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
report.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[2]
locked_sha = "21a7f44fd0765fcc5194130b28767786eba1d1e7"
if "SOURCE_SHA=" + locked_sha not in (root / "source.lock").read_text():
    sys.exit("Pinned source moved; review driver compatibility before updating")
profile = {}
for line in (root / "source.lock").read_text().splitlines():
    if "=" in line and not line.startswith("#"):
        key, value = line.split("=", 1)
        profile[key] = value
if (root / "patches/bore.lock").is_file():
    for line in (root / "patches/bore.lock").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            profile[key] = value
if (root / "patches/lab.lock").is_file():
    for line in (root / "patches/lab.lock").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            profile[key] = value
# Accept ONLY the exact local ABIs defined for this source; never permit an
# arbitrary KERNELRELEASE just because it happens to share the pinned SHA.
# Derived from source.lock + the patch locks (the same values
# scripts/tier-profile.sh uses) so an ABI bump cannot leave a stale copy here.
kv = profile.get("KERNEL_VERSION", "")
cr = profile.get("MBP51_CONFIG_REV", "")
legacy = profile.get("MBP51_LEGACY_SUFFIX", "")
if not (kv and cr and legacy and profile.get("BORE_PATCH_REV") and
        profile.get("LAB_PROFILE_REV")):
    sys.exit("source.lock/patches locks are missing KERNEL_VERSION, "
             "MBP51_CONFIG_REV, MBP51_LEGACY_SUFFIX, BORE_PATCH_REV or "
             "LAB_PROFILE_REV; refusing to guess a kernel ABI")
allowed_releases = {
    kv + legacy + "-" + cr,
    kv + "-mbp51-daily-g" + locked_sha[:8] + "-v1-" + cr,
    kv + "-mbp51-bore-g" + locked_sha[:8] + "-" + profile["BORE_PATCH_REV"] + "-" + cr,
    kv + "-mbp51-lab-g" + locked_sha[:8] + "-" + profile["LAB_PROFILE_REV"] + "-" + cr,
}
if release not in allowed_releases:
    sys.exit("Unsupported locked development-kernel release: " + release +
             " (expected one of: " + ", ".join(sorted(allowed_releases)) + ")")
changes = []

def exact(path, old, new, count):
    file = src / path
    body = file.read_text()
    found = body.count(old)
    if found != count:
        raise RuntimeError(f"{path}: expected {count} occurrences, found {found} of {old!r}")
    result = body.replace(old, new)
    file.write_text(result)
    changes.append(f"{path} modified={count} sha256={hashlib.sha256(result.encode()).hexdigest()}")

# Source labels itself 7.3.0, but has the 7.4-development cfg80211 callbacks.
exact("src/wl/sys/wl_cfg80211_hybrid.c",
      "u8 key_idx, bool pairwise,",
      "u8 key_idx, enum nl80211_key_type type,",
      18)

# The ndo_do_ioctl hook is no longer in struct net_device_ops in this commit.
f = src / "src/wl/sys/wl_linux.c"
body = f.read_text()
updated, count = re.subn(r"(?m)^\s*\.ndo_do_ioctl\s*=\s*wl_ioctl\s*,?\s*$", "", body)
if count != 2:
    raise RuntimeError(f"Expected two deleted net_device_ops callbacks, found {count}")
f.write_text(updated)
changes.append(f"src/wl/sys/wl_linux.c removed_callbacks={count}")

# Modern Linux rejects flush_scheduled_work() on a system-wide queue.
# The existing wl_down wait loop still calls schedule(); follow the
# maintained Debian/RPMFusion approach and remove the global flush.
exact("src/wl/sys/wl_linux.c",
      "flush_scheduled_work();",
      "/* legacy global workqueue flush removed; schedule() remains */",
      1)

# Keep the intended shim while avoiding macro-redefinition warnings.
exact("src/wl/sys/wl_iw.h",
      "#define isprint(c) bcm_isprint(c)",
      "#ifdef isprint\n#undef isprint\n#endif\n#define isprint(c) bcm_isprint(c)",
      1)

# Mark intentional fallthrough; preserve original switch-case behavior.
exact("src/wl/sys/wl_cfg80211_hybrid.c",
      'WL_DBG(("network eap\\n"));',
      'WL_DBG(("network eap\\n"));\n\t\tfallthrough;',
      1)

# Legacy cosmetic warnings only; do NOT globally disable -Werror.
f = src / "Makefile"
original = f.read_text()
f.write_text(original + "\n# MBP5,1: targeted legacy warning categories, real errors remain fatal\n" +
             "ccflags-y += -Wno-error=empty-body -Wno-error=misleading-indentation\n")
changes.append("Makefile narrow_warning_compatibility=empty-body,misleading-indentation")

(report / "patch-manifest.txt").write_text(
    "source_commit=" + locked_sha + "\nkernel_release=" + release + "\n" +
    "\n".join(changes) + "\n"
)
print("\n".join(changes))
