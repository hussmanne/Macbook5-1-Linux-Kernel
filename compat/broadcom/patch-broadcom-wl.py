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
locked_sha = "330517c63aa9b48227b6ab45f01003effac77ae4"
if "SOURCE_SHA=" + locked_sha not in (root / "source.lock").read_text():
    sys.exit("Pinned source moved; review driver compatibility before updating")
if release != "7.3.0-mbp51-extreme":
    sys.exit("Unsupported target release: " + release)
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
      6)

# The ndo_do_ioctl hook is no longer in struct net_device_ops in this commit.
f = src / "src/wl/sys/wl_linux.c"
body = f.read_text()
updated, count = re.subn(r"(?m)^\s*\.ndo_do_ioctl\s*=\s*wl_ioctl\s*,?\s*$", "", body)
if count != 2:
    raise RuntimeError(f"Expected two deleted net_device_ops callbacks, found {count}")
f.write_text(updated)
changes.append(f"src/wl/sys/wl_linux.c removed_callbacks={count}")

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
