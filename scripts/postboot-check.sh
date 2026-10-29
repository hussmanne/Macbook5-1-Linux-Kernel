#!/usr/bin/env bash
# Read-only MacBookPro5,1 post-boot acceptance check.
#
# Runs the same expectations on linux-lts, legacy, Daily, BORE and Lab so the
# outputs are directly comparable. It changes no system state: no suspend, no
# GPU rail change, no PowerTOP tune, no package install, no boot edit.
#
# Usage: bash scripts/postboot-check.sh [OUTPUT_FILE] [--no-wifi]
#   --no-wifi   the kernel was installed with install/activate-*-kernel.sh
#               --no-wifi, so a missing wl module is expected. Downgrades that
#               check from FAIL to WARN; everything else is unchanged.
# Exit status: 0 = no FAIL, 1 = at least one FAIL (WARN does not fail).
set -uo pipefail

out=""
wifi_expected=1
for arg in "$@"; do
  case "$arg" in
    --no-wifi) wifi_expected=0 ;;
    -h|--help) printf 'Usage: %s [OUTPUT_FILE] [--no-wifi]\n' "$0"; exit 0 ;;
    --*) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    *) out=$arg ;;
  esac
done
results=()
fails=0
warns=0

note() { printf '%s\n' "$*"; }
ok()   { results+=("PASS  $1  $2"); printf 'PASS  %-22s %s\n' "$1" "$2"; }
warn() { results+=("WARN  $1  $2"); warns=$((warns + 1)); printf 'WARN  %-22s %s\n' "$1" "$2"; }
fail() { results+=("FAIL  $1  $2"); fails=$((fails + 1)); printf 'FAIL  %-22s %s\n' "$1" "$2"; }

have() { command -v "$1" >/dev/null 2>&1; }
first_line() { [[ -r "$1" ]] && head -n 1 "$1" 2>/dev/null || true; }
can_root() { have sudo && sudo -n true 2>/dev/null; }

section() { printf '\n--- %s ---\n' "$1"; }

rel=$(uname -r)
note "MacBookPro5,1 post-boot acceptance check"
note "date=$(date -Iseconds)"
note "kernel=$rel"
note "cmdline=$(first_line /proc/cmdline)"
note "product=$(first_line /sys/class/dmi/id/product_name)"
if [[ "$(first_line /sys/class/dmi/id/product_name)" != "MacBookPro5,1" ]]; then
  warn machine "not a MacBookPro5,1; results are not comparable to other tiers"
fi

section "kernel configuration"
if [[ -r /proc/config.gz ]]; then
  cfg=$(zcat /proc/config.gz 2>/dev/null || true)
  ok config "/proc/config.gz readable ($(printf '%s' "$cfg" | wc -l) lines)"
  for sym in CONFIG_CPU_MITIGATIONS CONFIG_IKCONFIG_PROC CONFIG_FRAMEBUFFER_CONSOLE CONFIG_SCHED_BORE; do
    note "  ${sym}: $(printf '%s\n' "$cfg" | grep -E "^(# )?${sym}[= ]" | head -n 1)"
  done
  if grep -q '^CONFIG_USER_NS=y' <<<"$cfg"; then
    ok user_ns "compiled in"
  else
    fail user_ns "CONFIG_USER_NS missing"
  fi
  if grep -qE '^CONFIG_CPU_MITIGATIONS=' <<<"$cfg"; then
    ok cpu_mitigations "$(grep -m1 -E '^CONFIG_CPU_MITIGATIONS=' <<<"$cfg")"
  elif grep -q '^# CONFIG_CPU_MITIGATIONS is not set' <<<"$cfg"; then
    ok cpu_mitigations "CONFIG_CPU_MITIGATIONS is not set (user-directed security trade-off)"
  else
    warn cpu_mitigations "symbol absent; cannot confirm mitigation policy"
  fi
else
  warn config "/proc/config.gz absent (CONFIG_IKCONFIG_PROC not enabled) - cannot prove shipped config"
fi

section "userspace isolation recovered after v1"
if [[ -r /proc/sys/user/max_user_namespaces ]] &&
   (( $(first_line /proc/sys/user/max_user_namespaces) > 0 )); then
  ok user_ns_runtime "max_user_namespaces=$(first_line /proc/sys/user/max_user_namespaces)"
else
  fail user_ns_runtime "user namespaces unavailable"
fi
if [[ -r /sys/fs/cgroup/cgroup.controllers ]]; then
  grep -qw memory /sys/fs/cgroup/cgroup.controllers &&
    ok memcg "memory controller in cgroup2" || fail memcg "memory controller missing"
else
  fail memcg "cgroup2 not mounted"
fi
[[ -r /proc/pressure/memory ]] && ok psi "memory PSI readable" || fail psi "PSI missing"
if [[ "$(findmnt -no OPTIONS / 2>/dev/null)" == *noacl* ]]; then
  fail btrfs_acl "root mounted noacl"
else
  ok btrfs_acl "no noacl mount option"
fi

section "console (can you read a kernel panic on this machine?)"
if [[ -s /proc/fb ]] && grep -qvE '^\s*$' /proc/fb 2>/dev/null; then
  ok console "/proc/fb: $(tr '\n' ' ' </proc/fb)"
else
  fail console "no framebuffer console - a failed X session will be a black screen"
fi

section "audio"
cards=$(grep -c '^ *[0-9]' /proc/asound/cards 2>/dev/null)
cards=${cards//[^0-9]/}
cards=${cards:-0}
if (( cards > 0 )); then
  ok alsa_cards "$cards card(s): $(tr '\n' '|' </proc/asound/cards | cut -c1-120)"
  if have grep && grep -rqi 'realtek' /proc/asound/card*/codec#* 2>/dev/null; then
    ok hda_realtek "Realtek codec enumerated"
  else
    warn hda_realtek "no Realtek codec found (headphones/speakers may be silent)"
  fi
else
  fail alsa_cards "no ALSA soundcards"
fi

section "network"
if have modinfo && modinfo -k "$rel" -n wl >/dev/null 2>&1; then
  wl_path=$(modinfo -k "$rel" -n wl)
  wl_ver=$(modinfo -k "$rel" -F vermagic wl)
  note "  wl path: $wl_path"
  case "$wl_path" in
    */updates/mbp51/wl.ko) ok wl_path "private module path" ;;
    *) warn wl_path "unexpected wl path (stock DKMS may shadow the private build?)" ;;
  esac
  [[ "$wl_ver" == "$rel "* ]] && ok wl_vermagic "$wl_ver" || fail wl_vermagic "vermagic '$wl_ver' != '$rel'"
  lspci -nn 2>/dev/null | grep -q '14e4:432b' && ok bcm4322 "14e4:432b present" || warn bcm4322 "card not visible"
elif (( wifi_expected )); then
  fail wl_path "no wl module for $rel - Wi-Fi unavailable on this boot"
else
  warn wl_path "no wl module for $rel (expected: installed with --no-wifi)"
fi
if have nmcli; then
  timeout -k 2 8 nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | sed 's/^/  /' || true
fi

section "graphics and backlight"
drm_cards=$(ls /dev/dri/card* 2>/dev/null | wc -l)
drm_render=$(ls /dev/dri/renderD* 2>/dev/null | wc -l)
if (( drm_cards >= 1 )); then
  ok drm_nodes "card=$drm_cards render=$drm_render"
else
  fail drm_nodes "no DRM devices"
fi
for d in /sys/class/drm/card*/device/driver; do
  [[ -e "$d" ]] || continue
  note "  $(basename "${d%/device/driver}"): $(basename "$(readlink -f "$d")")"
done
bl_count=0
for d in /sys/class/backlight/*; do
  [[ -d "$d" ]] || continue
  bl_count=$((bl_count + 1))
  note "  backlight $(basename "$d"): brightness=$(first_line "$d/brightness") max=$(first_line "$d/max_brightness")"
done
if (( bl_count > 0 )); then
  if compgen -G "/sys/class/backlight/*gmux*" >/dev/null; then
    ok backlight "gmux backlight present"
  else
    warn backlight "no gmux backlight (acpi_video may be controlling the panel)"
  fi
else
  fail backlight "no backlight device"
fi
if can_root; then
  timeout -k 2 5 sudo -n cat /sys/kernel/debug/vgaswitcheroo/switch 2>/dev/null | sed 's/^/  /' || true
else
  note "  vgaswitcheroo: run sudo -v first to include the switch state"
fi

section "power supply and battery"
bats=0
for d in /sys/class/power_supply/*; do
  [[ -d "$d" ]] || continue
  note "  $(basename "$d"): type=$(first_line "$d/type") status=$(first_line "$d/status")"
  [[ "$(first_line "$d/type")" == "Battery" ]] && bats=$((bats + 1))
done
if (( bats > 0 )); then
  ok battery "$bats battery device(s)"
  if [[ -r /sys/class/power_supply/BAT0/power_now ]]; then
    ok power_now "power_now=$(first_line /sys/class/power_supply/BAT0/power_now) uW"
  else
    warn power_now "no power_now; use energy_now deltas or an AC wattmeter"
  fi
else
  warn battery "no BAT* device: power measurement impossible on this boot (dead/disconnected battery is as likely as a kernel fault)"
fi
[[ -r /sys/class/power_supply/ADP1/online ]] &&
  ok ac_adapter "ADP1 online=$(first_line /sys/class/power_supply/ADP1/online)" || warn ac_adapter "ADP1 missing"

section "thermal and memory"
temp_seen=0
for f in /sys/class/hwmon/hwmon*/temp*_input /sys/class/thermal/thermal_zone*/temp; do
  [[ -r "$f" ]] || continue
  v=$(first_line "$f")
  [[ "$v" =~ ^-?[0-9]+$ ]] || continue
  printf '  %s = %s\n' "$f" "$v"
  temp_seen=$((temp_seen + 1))
done
(( temp_seen > 0 )) && ok thermals "$temp_seen sensor(s) readable" || warn thermals "no readable temperature sensors"
if compgen -G "/sys/class/hwmon/hwmon*/fan*_input" >/dev/null; then
  ok fans "$(for f in /sys/class/hwmon/hwmon*/fan*_input; do printf '%s ' "$(first_line "$f")"; done)"
else
  warn fans "no fan tachometer exposed (applesmc not loaded?)"
fi
if swapon --show=NAME,ALGORITHM 2>/dev/null | grep -q zram; then
  note "  $(swapon --show=NAME,ALGORITHM 2>/dev/null | tr '\n' ' ')"
  if [[ -r /sys/block/zram0/comp_algorithm ]] &&
     grep -q '\[lz4\]' /sys/block/zram0/comp_algorithm; then
    ok zram "lz4 backend active"
  else
    warn zram "zram active but not using lz4: $(first_line /sys/block/zram0/comp_algorithm)"
  fi
else
  warn zram "no zram swap active (zram-generator not deployed?)"
fi
[[ -r /proc/pressure/memory ]] && ok psi_sample "$(grep '^some' /proc/pressure/memory | head -n 1)"

section "apple platform"
if compgen -G "/sys/class/hwmon/hwmon*" >/dev/null &&
   grep -lq 'applesmc' /sys/class/hwmon/hwmon*/name 2>/dev/null; then
  ok applesmc "SMC sensors bound"
else
  warn applesmc "applesmc not providing hwmon data"
fi
if have lsmod && lsmod | grep -q '^applesmc'; then
  ok applesmc_module "applesmc module loaded"
fi

section "boot health"
if have systemctl; then
  failed=$(systemctl --failed --no-pager --plain 2>/dev/null | awk 'NR > 1 && NF { print $1 }' | tr '\n' ' ')
  if [[ -z "$failed" ]]; then
    ok units "no failed systemd units"
  else
    warn units "failed: $failed"
  fi
fi
if can_root; then
  errcount=$(timeout -k 2 10 sudo -n journalctl -k -b -p err --no-pager 2>/dev/null | grep -c '')
  errcount=${errcount//[^0-9]/}
  errcount=${errcount:-0}
  warncount=$(timeout -k 2 10 sudo -n journalctl -k -b -p warning..warning --no-pager 2>/dev/null | grep -c '')
  warncount=${warncount//[^0-9]/}
  warncount=${warncount:-0}
  (( errcount > 0 )) && warn kernel_errors "$errcount kernel error line(s) this boot" \
    || ok kernel_errors "no kernel error lines this boot"
  (( warncount > 0 )) && warn kernel_warnings "$warncount kernel warning line(s) this boot" \
    || ok kernel_warnings "no kernel warning lines this boot"
else
  warn journal "no cached sudo; kernel error/warning counts omitted"
fi

printf '\n--- summary ---\n'
printf 'PASS=%s WARN=%s FAIL=%s\n' \
  "$(( ${#results[@]} - warns - fails ))" "$warns" "$fails"
if (( fails > 0 )); then
  printf '\nFailed requirements:\n'
  for r in "${results[@]}"; do
    [[ "$r" == FAIL* ]] && printf '  %s\n' "$r"
  done
fi

if [[ -n "$out" ]]; then
  mkdir -p "$(dirname "$out")" 2>/dev/null || true
  {
    printf 'kernel=%s\ndate=%s\n' "$rel" "$(date -Iseconds)"
    for r in "${results[@]}"; do printf '%s\n' "$r"; done
  } >"$out" && note "written: $out"
fi

if (( fails > 0 )); then
  note "RESULT: NOT ACCEPTED - fix FAIL items before promoting this kernel"
  exit 1
fi
note "RESULT: ACCEPTED (review WARN items and record them as known state)"
exit 0
