#!/usr/bin/env bash
# Explicit BORE installer wrapper. All safety gates live in the shared tier
# installer; this wrapper only selects the independently packaged BORE tier.
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
export MBP51_TIER=bore
# Invoke through bash: exec on a non-executable file fails with
# "Permission denied" regardless of how this wrapper was started.
exec bash "$root/activate-daily-kernel.sh" "$@"
