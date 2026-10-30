#!/usr/bin/env bash
# Idle-power measurement for the MacBookPro5,1.
#
# Answers the only question that matters for battery life: how many watts does
# the machine draw while doing nothing? Every "tweak" in
# docs/POWER-PERF-2026-10-29.md is worth exactly what this script says it is,
# so run it before and after each change instead of trusting the estimate.
#
# One CSV row per run, so two configurations compare directly:
#
#   sudo ./scripts/power-idle.sh --label baseline --out /var/tmp/power.csv
#   ... change exactly one thing ...
#   sudo ./scripts/power-idle.sh --label gpu-off  --out /var/tmp/power.csv
#
# Read-only by construction: it reads sysfs and writes nothing but the CSV.
#
# Notes
#  * Measuring on AC is meaningless (the charger supplies whatever the machine
#    asks for), so AC-connected runs are refused unless --allow-ac is given.
#  * power_now is used when the firmware provides it; otherwise watts come from
#    the energy_now delta, which works on any ACPI battery.
#  * MBP51_SYSROOT exists so the test script can point this at a synthetic
#    sysfs tree; it is not meant to be set in normal use.
set -euo pipefail
shopt -s nullglob

root=${MBP51_SYSROOT:-/}
seconds=120
settle=30
label=default
out=""
allow_ac=0
dry_run=0

usage() {
  cat <<'EOF'
Usage: power-idle.sh [options]

  --label NAME     name recorded in the CSV row (default: default)
  --out FILE       append one CSV row to FILE (header written if absent)
  --seconds N      measurement window, >= 1 (default: 120)
  --settle N       idle delay before measuring, >= 0 (default: 30)
  --allow-ac       measure even though the AC adapter is connected
  --dry-run        validate inputs and print the plan, measure nothing
  -h, --help       this text

Exit: 0 measured, 2 bad arguments, 3 no battery, 4 on AC, 5 no usable
source of power readings.
EOF
}

die() { printf '%s\n' "$2" >&2; exit "$1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)    [[ $# -ge 2 ]] || die 2 "--label needs a value";   label=$2; shift 2 ;;
    --out)      [[ $# -ge 2 ]] || die 2 "--out needs a value";     out=$2;   shift 2 ;;
    --seconds)  [[ $# -ge 2 ]] || die 2 "--seconds needs a value"; seconds=$2; shift 2 ;;
    --settle)   [[ $# -ge 2 ]] || die 2 "--settle needs a value";  settle=$2;  shift 2 ;;
    --allow-ac) allow_ac=1; shift ;;
    --dry-run)  dry_run=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage >&2; die 2 "unknown option: $1" ;;
  esac
done

[[ $seconds =~ ^[0-9]+$ ]] || die 2 "--seconds must be an integer >= 1"
[[ $settle  =~ ^[0-9]+$ ]] || die 2 "--settle must be an integer >= 0"
(( seconds >= 1 )) || die 2 "--seconds must be >= 1"

first_line() { head -n1 "$1" 2>/dev/null || true; }

# Integers only: a sysfs file that is missing, empty or holds "N/A" becomes 0.
read_int() {
  local v
  v=$(first_line "$1")
  if [[ $v =~ ^-?[0-9]+$ ]]; then printf '%s' "$v"; else printf '0'; fi
}

find_battery() {
  local d
  for d in "$root"/sys/class/power_supply/BAT*; do
    if [[ -d $d ]]; then printf '%s' "$d"; return 0; fi
  done
  return 1
}

ac_online() {
  local d
  for d in "$root"/sys/class/power_supply/*; do
    [[ -r $d/type ]] || continue
    [[ "$(first_line "$d/type")" == "Mains" ]] || continue
    first_line "$d/online"
    return 0
  done
  printf 'unknown'
}

# Aggregate cpuidle residency across all CPUs. State 0 is the shallowest
# (poll/C1); the deepest reachable state is what actually saves power.
# Echoes: total_us shallow_us deepest_us deepest_name
cstate_sample() {
  local cpu st idx name t max_idx=-1
  local total=0 shallow=0
  local -A by_idx=() name_of=()
  for cpu in "$root"/sys/devices/system/cpu/cpu[0-9]*/cpuidle; do
    [[ -d $cpu ]] || continue
    idx=0
    for st in "$cpu"/state[0-9]*; do
      [[ -d $st ]] || continue
      name=$(first_line "$st/name")
      t=$(read_int "$st/time")
      total=$(( total + t ))
      by_idx[$idx]=$(( ${by_idx[$idx]:-0} + t ))
      if [[ -z ${name_of[$idx]:-} ]]; then name_of[$idx]=$name; fi
      if (( idx > max_idx )); then max_idx=$idx; fi
      idx=$(( idx + 1 ))
    done
  done
  if (( max_idx < 0 )); then printf '0 0 0 none'; return 0; fi
  if [[ -n ${by_idx[0]:-} ]]; then shallow=${by_idx[0]}; fi
  printf '%s %s %s %s' "$total" "$shallow" "${by_idx[$max_idx]:-0}" "${name_of[$max_idx]:-unknown}"
}

avg_mhz() {
  local f total=0 n=0
  for f in "$root"/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
    [[ -r $f ]] || continue
    total=$(( total + $(read_int "$f") ))
    n=$(( n + 1 ))
  done
  if (( n == 0 )); then printf '0'; return 0; fi
  awk -v t="$total" -v n="$n" 'BEGIN { printf "%.0f", t / n / 1000 }'
}

max_temp_c() {
  local z v max=-100000
  for z in "$root"/sys/class/thermal/thermal_zone[0-9]*/temp; do
    [[ -r $z ]] || continue
    v=$(read_int "$z")
    if (( v > max )); then max=$v; fi
  done
  if (( max == -100000 )); then printf ''; return 0; fi
  awk -v m="$max" 'BEGIN { printf "%.1f", m / 1000 }'
}

# "IGD=Pwr;DIG=Off" — enough to tell whether the discrete GPU is powered.
# A line looks like "1:DIG:+:Off:0000:02:00.0"; split on ':' and keep the
# name and the power state, not the PCI address.
gpu_state() {
  local f s="" line idx name sw pwr rest
  f="$root/sys/kernel/debug/vgaswitcheroo/switch"
  [[ -r $f ]] || { printf ''; return 0; }
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    IFS=: read -r idx name sw pwr rest <<<"$line"
    if [[ -n ${name:-} && -n ${pwr:-} ]]; then s+="${name}=${pwr};"; fi
  done < <(head -n 4 "$f" 2>/dev/null || true)
  printf '%s' "${s%;}"
}

if ! battery=$(find_battery); then
  die 3 "no battery under $root/sys/class/power_supply — cannot measure power on this machine"
fi
ac=$(ac_online)

if [[ $ac == "1" && $allow_ac -eq 0 ]]; then
  die 4 "AC adapter is connected; the reading would be the charger's, not the battery's. Unplug it, or pass --allow-ac."
fi

if (( dry_run )); then
  printf 'battery=%s\nac_online=%s\nlabel=%s\nsettle=%ss\nseconds=%ss\nout=%s\n' \
    "$battery" "$ac" "$label" "$settle" "$seconds" "${out:-<none>}"
  exit 0
fi

if (( settle > 0 )); then
  printf 'settling for %ss (keep the machine idle)...\n' "$settle" >&2
  sleep "$settle"
fi

p1=$(read_int "$battery/power_now")
e1=$(read_int "$battery/energy_now")
read -r _c_total_1 _c_shallow_1 _c_deep_1 _c_deep_name_1 <<<"$(cstate_sample)"

sleep "$seconds"

p2=$(read_int "$battery/power_now")
e2=$(read_int "$battery/energy_now")
read -r c_total_2 c_shallow_2 c_deep_2 c_deep_name <<<"$(cstate_sample)"

if (( p2 > 0 )); then
  watts=$(awk -v p="$p2" 'BEGIN { printf "%.2f", p / 1e6 }')
  source=power_now
elif (( e1 > 0 && e2 > 0 && e1 > e2 )); then
  # energy_now is µWh; µWh -> J is *3.6e-3, and W is J/s.
  watts=$(awk -v a="$e1" -v b="$e2" -v t="$seconds" 'BEGIN { printf "%.2f", (a - b) * 3.6e-3 / t }')
  source=energy_now
else
  die 5 "no usable power reading: power_now unreadable and energy_now did not drop. Is the battery discharging?"
fi

d_total=$(( c_total_2 - _c_total_1 ))
d_shallow=$(( c_shallow_2 - _c_shallow_1 ))
d_deep=$(( c_deep_2 - _c_deep_1 ))
c0_pct=$(awk -v s="$d_shallow" -v t="$d_total" 'BEGIN { if (t > 0) printf "%.1f", 100 * s / t }')
deep_pct=$(awk -v s="$d_deep" -v t="$d_total" 'BEGIN { if (t > 0) printf "%.1f", 100 * s / t }')
mhz=$(avg_mhz)
temp=$(max_temp_c)
gpu=$(gpu_state)
stamp=$(date -Is)

printf 'idle power : %s W (%s)\n' "$watts" "$source"
printf 'frequency : %s MHz average\n' "$mhz"
printf 'C-states  : %s%% in shallowest, %s%% in deepest (%s)\n' "${c0_pct:-n/a}" "${deep_pct:-n/a}" "$c_deep_name"
printf 'temperature: %s C\n' "${temp:-n/a}"
if [[ -n $gpu ]]; then printf 'GPU switch: %s\n' "$gpu"; fi
printf 'battery   : %s\n' "$battery"

if [[ -n $out ]]; then
  if [[ ! -s $out ]]; then
    printf '%s\n' "timestamp,label,seconds,watts,source,avg_mhz,c0_pct,deepest_pct,deepest_state,max_temp_c,ac_online,gpu_switch" > "$out"
  fi
  printf '%s\n' "$stamp,$label,$seconds,$watts,$source,$mhz,${c0_pct:-},${deep_pct:-},$c_deep_name,${temp:-},$ac,$gpu" >> "$out"
  printf 'appended  : %s\n' "$out"
fi
