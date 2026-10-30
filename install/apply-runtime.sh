#!/usr/bin/env bash
# Deploy the runtime templates under runtime/ onto an installed system.
#
# Before this script existed, exactly one file deployed them
# (install/archiso-install.sh). Everything else — the manual Arch path and the
# EndeavourOS machine this project is actually for — had no step at all, so
# "deploy the runtime templates" in INSTALL.md was an instruction with no
# command behind it.
#
# Best-effort by design: a missing optional package is a warning, not a
# failure. The machine must still come up, and a partially deployed power
# policy is better than an installer that aborts after partitioning.
#
# Idempotent: safe to re-run, and safe to run against a mounted target
# (--root /mnt) from a live ISO as well as against a running system.
#
# Examples:
#   sudo ./install/apply-runtime.sh                  # this system
#   sudo ./install/apply-runtime.sh --verify         # check what is deployed
#   sudo ./install/apply-runtime.sh --root /mnt      # from a live ISO
#   sudo ./install/apply-runtime.sh --enable-powertop  # opt in to power tuning
set -euo pipefail

root=/
verify_only=0
enable_powertop=0
warnings=0
errors=0

usage() {
  cat <<'EOF'
Usage: apply-runtime.sh [options]

  --root DIR         install root, default / (use /mnt from a live ISO)
  --enable-powertop  also enable mbp51-powertop.service. Off by default: the
                     global PowerTOP tuning is deliberately deferred until the
                     baseline boot has been qualified.
  --verify           report what is deployed; change nothing
  -h, --help         this text

Always deployed:
  zram-generator.conf  -> $ROOT/etc/systemd/zram-generator.conf
  99-mbp51-memory.conf -> $ROOT/etc/sysctl.d/99-mbp51-memory.conf
  mbp51-powertop.service -> $ROOT/etc/systemd/system/
  50-mbp51-powertop    -> $ROOT/usr/lib/systemd/system-sleep/

Exit: 0 clean or warnings only, 2 bad arguments, 3 a file could not be written.
EOF
}

warn() { printf 'WARN  %s\n' "$*" >&2; warnings=$((warnings + 1)); }
info() { printf '      %s\n' "$*"; }
step() { printf '==> %s\n' "$*"; }
die()  { printf '%s\n' "$2" >&2; exit "$1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)            [[ $# -ge 2 ]] || die 2 "--root needs a value"; root=$2; shift 2 ;;
    --enable-powertop) enable_powertop=1; shift ;;
    --verify)          verify_only=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 usage >&2; die 2 "unknown option: $1" ;;
  esac
done

repo=$(cd "$(dirname "$0")/.." && pwd)
[[ -d $root ]] || die 2 "install root does not exist: $root"
root=$(cd "$root" && pwd)
# A root that is not / has to look like a system, or we would scatter files
# into a random directory.
if [[ $root != / && ! -d $root/etc ]]; then
  die 2 "$root does not look like an install root (no etc/)"
fi

# One entry per runtime file: source, destination, mode.
deploy() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }
plan=$(
  deploy runtime/systemd/zram-generator.conf   etc/systemd/zram-generator.conf                644
  deploy runtime/sysctl.d/99-mbp51-memory.conf etc/sysctl.d/99-mbp51-memory.conf              644
  deploy runtime/systemd/mbp51-powertop.service etc/systemd/system/mbp51-powertop.service     644
  deploy runtime/system-sleep/50-mbp51-powertop usr/lib/systemd/system-sleep/50-mbp51-powertop 755
)

# --- verify ---------------------------------------------------------------
verify_all() {
  local src rel mode dest bad=0
  step "verifying runtime deployment under $root"
  while IFS=$'\t' read -r src rel mode; do
    dest="$root/$rel"
    if [[ -f $dest ]]; then
      if cmp -s "$repo/$src" "$dest"; then
        printf '  OK      %s\n' "$rel"
      else
        printf '  DIFFERS %s\n' "$rel"; bad=1
      fi
    else
      printf '  MISSING %s\n' "$rel"; bad=1
    fi
  done <<<"$plan"

  # zram-generator is what turns the config into an actual swap device.
  if command -v systemctl >/dev/null 2>&1; then
    local state
    state=$(systemctl --root="$root" is-enabled systemd-zram-setup@zram0.service 2>/dev/null || true)
    printf '  zram unit: %s\n' "${state:-unknown}"
  fi
  if [[ $verify_only -eq 1 ]]; then
    if (( bad )); then
      printf '\nDeployment is incomplete. Re-run without --verify to fix.\n' >&2
      return 1
    fi
    printf '\nAll runtime files are deployed and match the repository.\n'
  fi
  return 0
}

if [[ $verify_only -eq 1 ]]; then
  verify_all || exit 1
  exit 0
fi

# --- deploy ---------------------------------------------------------------
step "deploying runtime templates to $root"
while IFS=$'\t' read -r src rel mode; do
  [[ -f "$repo/$src" ]] || { printf 'ERROR missing in repo: %s\n' "$src" >&2; errors=$((errors + 1)); continue; }
  dest="$root/$rel"
  mkdir -p "$(dirname "$dest")"
  if install -m "$mode" "$repo/$src" "$dest" 2>/dev/null; then
    printf '  %s -> %s\n' "$src" "$rel"
  else
    printf 'ERROR could not write %s\n' "$dest" >&2
    errors=$((errors + 1))
  fi
done <<<"$plan"

# --- zram generator -------------------------------------------------------
# Without the package the config is inert and there is no swap at all.
if [[ -e "$root/usr/lib/systemd/system-generators/zram-generator" ]] ||
   [[ -e "$root/usr/bin/zramctl" ]] ||
   command -v zramctl >/dev/null 2>&1; then
  info "zram-generator present; zram0 will come up at next boot"
else
  warn "zram-generator does not appear to be installed in $root."
  warn "  The config is deployed but inert, and the machine will have NO swap."
  warn "  Install it with: pacman -S systemd-zram-generator"
fi

# --- sysctls --------------------------------------------------------------
if [[ $root == / ]]; then
  if command -v sysctl >/dev/null 2>&1; then
    step "applying sysctls now"
    # --system re-reads /etc/sysctl.d; failing here is not fatal, because the
    # files are already deployed and the next boot will pick them up.
    sysctl --system >/dev/null 2>&1 || warn "sysctl --system failed; values apply at next boot"
    swappiness_now=$(sysctl -n vm.swappiness 2>/dev/null || true)
    [[ -n ${swappiness_now:-} ]] && info "vm.swappiness = $swappiness_now"
  else
    warn "sysctl not found; memory tunables apply at next boot"
  fi
else
  info "sysctls will apply on first boot of $root"
fi

# --- powertop -------------------------------------------------------------
# Deliberately opt-in. The global PowerTOP tuning is deferred until the
# baseline boot is qualified; the system-sleep hook gates itself on this unit
# being enabled, so leaving it disabled also keeps resume untuned.
if [[ $enable_powertop -eq 1 ]]; then
  step "enabling mbp51-powertop.service"
  if [[ $root != / && ! -x "$root/usr/bin/powertop" ]]; then
    warn "powertop is not installed in $root; the unit will be skipped by its"
    warn "  own ConditionPathExists. Install it with: pacman -S powertop"
  fi
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl --root="$root" enable mbp51-powertop.service 2>/dev/null; then
      info "enabled"
    else
      warn "could not enable mbp51-powertop.service; enable it by hand after boot"
    fi
  else
    warn "systemctl not found; enable mbp51-powertop.service manually"
  fi
else
  info "mbp51-powertop.service left disabled (use --enable-powertop after the"
  info "  baseline boot passes; see docs/FRESH-ARCH-INSTALL.md)"
fi

printf '\n'
if (( errors )); then
  printf 'FAILED: %s file(s) could not be written.\n' "$errors" >&2
  exit 3
fi
if (( warnings )); then
  printf 'Deployed with %s warning(s). Re-run with --verify to confirm.\n' "$warnings"
else
  printf 'Runtime templates deployed cleanly. Re-run with --verify to confirm.\n'
fi
