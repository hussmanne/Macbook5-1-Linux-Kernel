#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for script in scripts/*.sh runtime/system-sleep/50-mbp51-powertop compat/broadcom/*.sh install/*.sh; do bash -n "$script"; done
for script in scripts/benchmark/*.sh; do bash -n "$script"; done
source "$PWD/scripts/tier-profile.sh"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]
[[ "$SOURCE_ARCHIVE_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$KERNEL_LOCALVERSION" == "-mbp51-extreme-g${SOURCE_SHA:0:8}-v2" ]]
grep -q 'no CPU_MITIGATIONS' scripts/configure.sh
grep -q 'no ZSWAP' scripts/configure.sh
grep -q 'CPU_MITIGATIONS' scripts/audit-config.sh
for feature in USER_NS MEMCG PSI BTRFS_FS_POSIX_ACL SND_HDA_CODEC_REALTEK ACPI_SBS; do
  grep -q "$feature" scripts/configure.sh
  grep -q "$feature" scripts/audit-config.sh
done
grep -q 'readlink -f' install/activate-custom-kernel.sh
grep -q 'sudo grep -Fq' install/activate-custom-kernel.sh
source "$PWD/patches/bore.lock"
[[ "$BORE_TARGET_SOURCE_SHA" == "$SOURCE_SHA" ]]
[[ "$(sha256sum "$PWD/$BORE_PATCH_FILE" | cut -d' ' -f1)" == "$BORE_PATCH_SHA256" ]]
grep -q 'git apply --check --whitespace=error' scripts/apply-tier-patches.sh
bash scripts/test-tier-profiles.sh
grep -q '^ExecStart=/usr/bin/powertop --auto-tune' runtime/systemd/mbp51-powertop.service
python3 -m py_compile compat/broadcom/patch-broadcom-wl.py
echo "Static validation passed; compilation not yet proven."
