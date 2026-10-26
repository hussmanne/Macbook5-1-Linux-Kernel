#!/usr/bin/env bash
# Explicit BORE installer wrapper. All safety gates live in the shared tier
# installer; this wrapper only selects the independently packaged BORE tier.
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
export MBP51_TIER=bore
exec "$root/activate-daily-kernel.sh" "$@"
