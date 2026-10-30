#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for script in scripts/*.sh runtime/system-sleep/50-mbp51-powertop compat/broadcom/*.sh install/*.sh; do bash -n "$script"; done
for script in scripts/benchmark/*.sh; do bash -n "$script"; done
bash -n tools/mbp51-hardware-survey.sh
# Installers and wrappers must be executable and must not exec a non-executable
# file: activate-bore/lab used to `exec` activate-daily-kernel.sh directly, and
# no installer carried the exec bit in git, so both wrappers failed outright.
# scripts/tier-profile.sh and scripts/benchmark/common.sh are sourced
# libraries ("Source this from other scripts"), so they stay 100644.
for script in install/*.sh scripts/*.sh; do
  case "$script" in
    scripts/tier-profile.sh|scripts/benchmark/common.sh) continue ;;
  esac
  [[ -x "$script" ]] || { echo "Not executable: $script" >&2; exit 1; }
done
grep -q 'exec bash "$root/activate-daily-kernel.sh"' install/activate-bore-kernel.sh
grep -q 'exec bash "$root/activate-daily-kernel.sh"' install/activate-lab-kernel.sh
for script in install/activate-daily-kernel.sh install/activate-custom-kernel.sh; do
  grep -q 'grub-mkrelpath' "$script"
  grep -q 'grub-probe' "$script"
  ! grep -qE 'linux \$subvol/boot/' "$script"
done
grep -q -- '--no-wifi' install/activate-daily-kernel.sh
grep -q -- '--no-wifi' scripts/postboot-check.sh
bash tools/mbp51-hardware-survey.sh --help >/dev/null
source "$PWD/scripts/tier-profile.sh"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]
[[ "$SOURCE_ARCHIVE_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$KERNEL_LOCALVERSION" == "-mbp51-extreme-g${SOURCE_SHA:0:8}-v2-${MBP51_CONFIG_REV}" ]]
[[ "$KERNEL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$MBP51_KERNEL_RELEASE" == "$KERNEL_VERSION$KERNEL_LOCALVERSION" ]]
grep -q 'no CPU_MITIGATIONS' scripts/configure.sh
grep -q 'no ZSWAP' scripts/configure.sh
# Swap and compressed RAM are easy to regress silently: a dropped sysctl or a
# zram-generator setting that no longer matches the built backend fails at boot
# with "'lz4' is not a valid compression algorithm" and no other symptom.
for setting in 'vm.swappiness = 100' 'vm.page-cluster = 0' \
  'vm.watermark_boost_factor = 0' 'vm.watermark_scale_factor = 125'; do
  grep -qxF "$setting" runtime/sysctl.d/99-mbp51-memory.conf
done
grep -qxF 'compression-algorithm = lz4' runtime/systemd/zram-generator.conf
grep -qxF 'swap-priority = 100' runtime/systemd/zram-generator.conf
grep -q 'zram-size = min(ram / 2, 4096)' runtime/systemd/zram-generator.conf
grep -q 'ZRAM_BACKEND_LZ4' scripts/configure.sh
grep -q 'ZRAM_BACKEND_LZ4' scripts/audit-config.sh
grep -q 'CPU_MITIGATIONS' scripts/audit-config.sh
for feature in USER_NS MEMCG PSI SWAP BTRFS_FS_POSIX_ACL SND_HDA_CODEC_REALTEK ACPI_SBS; do
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
bash scripts/test-installer-modes.sh
bash scripts/test-power-idle.sh
grep -q '^ExecStart=/usr/bin/powertop --auto-tune' runtime/systemd/mbp51-powertop.service
python3 -m py_compile compat/broadcom/patch-broadcom-wl.py
echo "Static validation passed; compilation not yet proven."
