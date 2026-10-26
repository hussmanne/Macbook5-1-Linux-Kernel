#!/usr/bin/env bash
# Explicit Extreme Lab installer wrapper. The first Lab profile is a real,
# feature-preserving HZ=250 configuration experiment; it does not perform
# voltage writes, GPU rail changes, firmware changes, or disk changes.
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
export MBP51_TIER=lab
exec "$root/activate-daily-kernel.sh" "$@"
