#!/usr/bin/env bash
# Tests for scripts/power-idle.sh against a synthetic sysfs tree.
#
# The real script reads /sys, which a sandbox (and CI) does not have a battery
# in. MBP51_SYSROOT lets the same code run against fixtures, so the parsing and
# the watts arithmetic are exercised without a MacBookPro5,1 present.
set -euo pipefail
cd "$(dirname "$0")/.."
script=$PWD/scripts/power-idle.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0 fail=0
ok()   { printf '  ok  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1" >&2; fail=$((fail+1)); }

# --- fixture -------------------------------------------------------------
fixture() {
  local root=$1
  mkdir -p "$root/sys/class/power_supply/BAT0" "$root/sys/class/power_supply/ADP1"
  printf 'Battery\n'     > "$root/sys/class/power_supply/BAT0/type"
  printf 'Discharging\n' > "$root/sys/class/power_supply/BAT0/status"
  printf '50000000\n'    > "$root/sys/class/power_supply/BAT0/energy_now"
  printf '12000000\n'    > "$root/sys/class/power_supply/BAT0/power_now"
  printf 'Mains\n'       > "$root/sys/class/power_supply/ADP1/type"
  printf '0\n'           > "$root/sys/class/power_supply/ADP1/online"
  local cpu st
  local -a names=(POLL C1 C3) times=(1000000 2000000 5000000)
  for cpu in 0 1; do
    for st in 0 1 2; do
      mkdir -p "$root/sys/devices/system/cpu/cpu$cpu/cpuidle/state$st"
      printf '%s\n' "${names[$st]}" > "$root/sys/devices/system/cpu/cpu$cpu/cpuidle/state$st/name"
      printf '%s\n' "${times[$st]}" > "$root/sys/devices/system/cpu/cpu$cpu/cpuidle/state$st/time"
    done
    mkdir -p "$root/sys/devices/system/cpu/cpu$cpu/cpufreq"
    printf '2400000\n' > "$root/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq"
  done
  mkdir -p "$root/sys/class/thermal/thermal_zone0"
  printf '52000\n' > "$root/sys/class/thermal/thermal_zone0/temp"
  mkdir -p "$root/sys/kernel/debug/vgaswitcheroo"
  printf '0:IGD:+:Pwr:0000:00:02.0\n1:DIG:+:Off:0000:02:00.0\n' \
    > "$root/sys/kernel/debug/vgaswitcheroo/switch"
}

# expect_exit CODE DESCRIPTION -- command...
expect_exit() {
  local want=$1 desc=$2; shift 3
  local got=0
  "$@" >"$work/out" 2>"$work/err" || got=$?
  if [[ $got == "$want" ]]; then ok "$desc"; else
    bad "$desc (expected exit $want, got $got)"; sed 's/^/       /' "$work/err" >&2
  fi
}

echo "== power-idle.sh =="

# 1. No battery: refuse rather than report a number.
mkdir -p "$work/empty/sys/class/power_supply"
export MBP51_SYSROOT=$work/empty
expect_exit 3 "refuses when there is no battery" -- bash "$script" --seconds 1 --settle 0

# 2. Battery + AC connected: refuse, because the reading would be the charger's.
r=$work/onac; fixture "$r"
printf '1\n' > "$r/sys/class/power_supply/ADP1/online"
export MBP51_SYSROOT=$r
expect_exit 4 "refuses to measure while on AC" -- bash "$script" --seconds 1 --settle 0

# 3. --allow-ac overrides that, for deliberate charger-side measurements.
expect_exit 0 "--allow-ac permits an AC-connected run" -- \
  bash "$script" --seconds 1 --settle 0 --allow-ac --label ac --out "$work/ac.csv"

# 4. Normal discharge: power_now is used directly.
r=$work/normal; fixture "$r"
export MBP51_SYSROOT=$r
expect_exit 0 "measures a discharging battery" -- \
  bash "$script" --seconds 1 --settle 0 --label base --out "$work/power.csv"
if [[ -s $work/power.csv ]]; then
  row=$(tail -n1 "$work/power.csv")
  case $row in
    *,base,1,12.00,power_now,2400,*) ok "12 W from power_now, 2400 MHz, source=power_now" ;;
    *) bad "unexpected CSV row: $row" ;;
  esac
  head -n1 "$work/power.csv" | grep -q '^timestamp,label,seconds,watts,source' &&
    ok "CSV header written once" || bad "CSV header missing"
  case $row in
    *"DIG=Off"*) ok "GPU switch state recorded as DIG=Off" ;;
    *) bad "GPU switch state not recorded: $row" ;;
  esac
  # A second run appends rather than rewriting the header.
  bash "$script" --seconds 1 --settle 0 --label second --out "$work/power.csv" >/dev/null
  [[ $(grep -c '^timestamp' "$work/power.csv") == 1 ]] &&
    ok "second run appends, header not duplicated" || bad "header duplicated"
  [[ $(wc -l < "$work/power.csv") == 3 ]] &&
    ok "two measurements recorded" || bad "expected 3 lines, got $(wc -l < "$work/power.csv")"
else
  bad "no CSV written"
fi

# 5. No power_now but a falling energy_now: derive watts from the delta.
r=$work/energy; fixture "$r"
rm -f "$r/sys/class/power_supply/BAT0/power_now"
export MBP51_SYSROOT=$r
( i=0; while (( i < 12 )); do
    printf '%s\n' $(( 50000000 - i * 100000 )) > "$r/sys/class/power_supply/BAT0/energy_now"
    for c in 0 1; do
      for st in 0 1 2; do
        printf '%s\n' $(( (1000000 + i * 100000) * (st + 1) )) \
          > "$r/sys/devices/system/cpu/cpu$c/cpuidle/state$st/time"
      done
    done
    i=$((i+1)); sleep 1
  done ) &
writer=$!
expect_exit 0 "falls back to the energy_now delta" -- \
  bash "$script" --seconds 3 --settle 0 --label e --out "$work/energy.csv"
kill "$writer" 2>/dev/null || true
wait "$writer" 2>/dev/null || true
row=$(tail -n1 "$work/energy.csv" 2>/dev/null || true)
case $row in
  *,energy_now,*) ok "reports source=energy_now" ;;
  *) bad "expected source=energy_now in: ${row:-<no row>}" ;;
esac
# Fields 7 and 8 are the C0 and deepest-state percentages.
deep_pct=$(printf '%s' "$row" | cut -d, -f8)
if [[ $deep_pct =~ ^[0-9]+\.[0-9]$ ]]; then
  ok "C-state residency computed (${deep_pct}% in deepest)"
else
  bad "C-state residency not computed, field 8 was '${deep_pct}'"
fi

# 6. Neither source usable (constant energy_now) must be an error, not "0.00 W".
r=$work/flat; fixture "$r"
rm -f "$r/sys/class/power_supply/BAT0/power_now"
export MBP51_SYSROOT=$r
expect_exit 5 "refuses to report 0 W when energy_now does not move" -- \
  bash "$script" --seconds 1 --settle 0

# 7. Argument validation.
expect_exit 2 "rejects --seconds 0" -- bash "$script" --seconds 0
expect_exit 2 "rejects an unknown option" -- bash "$script" --bogus
expect_exit 0 "--dry-run measures nothing" -- bash "$script" --dry-run
expect_exit 0 "--help exits 0" -- bash "$script" --help

echo
if (( fail > 0 )); then
  printf 'power-idle tests FAILED: %s passed, %s failed\n' "$pass" "$fail" >&2
  exit 1
fi
printf 'power-idle tests passed (%s checks).\n' "$pass"
