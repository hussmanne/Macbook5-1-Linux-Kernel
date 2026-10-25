#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for script in scripts/*.sh runtime/system-sleep/50-mbp51-powertop; do bash -n "$script"; done
source source.lock
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]
grep -q 'no CPU_MITIGATIONS' scripts/configure.sh
grep -q 'no ZSWAP' scripts/configure.sh
grep -q 'CPU_MITIGATIONS' scripts/audit-config.sh
grep -q '^ExecStart=/usr/bin/powertop --auto-tune' runtime/systemd/mbp51-powertop.service
echo "Static validation passed; compilation not yet proven."
