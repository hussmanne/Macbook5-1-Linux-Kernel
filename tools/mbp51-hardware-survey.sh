#!/usr/bin/env bash
# MacBookPro5,1 / MX Linux hardware survey.
#
# One-command, read-only evidence collector. It does not install packages,
# change sysctls, apply PowerTOP, switch GPUs, suspend, reboot, or write to
# system locations. It may run a short bounded CPU/hash workload to expose
# frequency scaling, wakeups, thermal behavior, and idle-state changes.
set -uo pipefail
shopt -s globstar nullglob

readonly SURVEY_VERSION="1.0.0"
readonly DEFAULT_SAMPLE_SECONDS=30
readonly DEFAULT_INTERVAL=2
readonly DEFAULT_LOAD_SECONDS=15
readonly COMMAND_TIMEOUT=45

out=""
sample_seconds="$DEFAULT_SAMPLE_SECONDS"
interval="$DEFAULT_INTERVAL"
load_seconds="$DEFAULT_LOAD_SECONDS"
no_sudo=0
no_load=0
keep_workload_logs=0
sudo_ready=0

usage() {
  cat <<'EOF'
MacBookPro5,1 hardware survey

Usage:
  mbp51-hardware-survey.sh [options]

Options:
  --output DIR       Evidence directory (default: ~/mbp51-survey-TIMESTAMP)
  --seconds N        Seconds per idle/load sampling phase (default: 30)
  --interval N       Seconds between samples (default: 2)
  --load-seconds N   CPU load duration inside the load phase (default: 15)
  --no-load          Skip the bounded CPU/hash workload phase
  --no-sudo          Do not request one read-only sudo authentication
  --keep-workload    Keep temporary workload logs in the evidence directory
  --version          Print version
  --help             Show this help

The program is read-only with respect to the system. It writes only the
selected output directory and a .tar.gz archive beside it.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
note() { printf '[survey] %s\n' "$*"; }

is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) [[ $# -ge 2 ]] || die "--output needs a directory"; out=$2; shift 2 ;;
    --seconds) [[ $# -ge 2 ]] || die "--seconds needs a number"; sample_seconds=$2; shift 2 ;;
    --interval) [[ $# -ge 2 ]] || die "--interval needs a number"; interval=$2; shift 2 ;;
    --load-seconds) [[ $# -ge 2 ]] || die "--load-seconds needs a number"; load_seconds=$2; shift 2 ;;
    --no-load) no_load=1; shift ;;
    --no-sudo) no_sudo=1; shift ;;
    --keep-workload) keep_workload_logs=1; shift ;;
    --version) printf '%s\n' "$SURVEY_VERSION"; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

is_uint "$sample_seconds" && (( sample_seconds >= 1 )) || die "--seconds must be a positive integer"
is_uint "$interval" && (( interval >= 1 )) || die "--interval must be a positive integer"
is_uint "$load_seconds" || die "--load-seconds must be a non-negative integer"

command -v bash >/dev/null 2>&1 || die "bash is required"
command -v date >/dev/null 2>&1 || die "date is required"
command -v mkdir >/dev/null 2>&1 || die "mkdir is required"
command -v tee >/dev/null 2>&1 || die "tee is required"

timestamp=$(date +%Y%m%d-%H%M%S)
if [[ -z "$out" ]]; then
  out="${HOME:-/tmp}/mbp51-survey-$timestamp"
fi
mkdir -p "$out" || die "cannot create output directory: $out"
raw="$out/raw"
samples="$out/samples"
mkdir -p "$raw" "$samples"

if [[ "$no_sudo" -eq 0 && "${EUID:-1}" -ne 0 && -x "$(command -v sudo 2>/dev/null || true)" ]]; then
  note "Requesting one optional sudo authentication for read-only kernel/PCI/debug data."
  if sudo -v; then
    sudo_ready=1
  else
    note "sudo authentication unavailable; continuing with unprivileged data."
  fi
fi

as_root() {
  if [[ "$sudo_ready" -eq 1 ]]; then
    sudo -n "$@"
  else
    "$@"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

capture_cmd() {
  local name=$1
  shift
  local file="$raw/$name.txt"
  {
    printf 'command='
    printf '%q ' "$@"
    printf '\nstarted=%s\n' "$(date -Iseconds 2>/dev/null || date)"
    if ! have "$1"; then
      printf 'status=not-installed\nprogram=%s\n' "$1"
      return 0
    fi
    timeout "$COMMAND_TIMEOUT" "$@" 2>&1
    local rc=$?
    printf '\nstatus=exit-%s\nfinished=%s\n' "$rc" "$(date -Iseconds 2>/dev/null || date)"
    return 0
  } >"$file" 2>&1
}

capture_root_cmd() {
  local name=$1
  shift
  local file="$raw/$name.txt"
  {
    printf 'command='; printf '%q ' "$@"; printf '\nstarted=%s\n' "$(date -Iseconds 2>/dev/null || date)"
    if ! have "$1"; then
      printf 'status=not-installed\nprogram=%s\n' "$1"
      return 0
    fi
    timeout "$COMMAND_TIMEOUT" as_root "$@" 2>&1
    local rc=$?
    printf '\nstatus=exit-%s\nfinished=%s\n' "$rc" "$(date -Iseconds 2>/dev/null || date)"
    return 0
  } >"$file" 2>&1
}

capture_shell() {
  local name=$1
  shift
  local file="$raw/$name.txt"
  {
    printf 'shell='; printf '%q ' "$@"; printf '\nstarted=%s\n' "$(date -Iseconds 2>/dev/null || date)"
    timeout "$COMMAND_TIMEOUT" bash -c "$*" 2>&1
    local rc=$?
    printf '\nstatus=exit-%s\nfinished=%s\n' "$rc" "$(date -Iseconds 2>/dev/null || date)"
    return 0
  } >"$file" 2>&1
}

capture_file() {
  local name=$1 path=$2
  local file="$raw/$name.txt"
  {
    printf 'path=%s\nstarted=%s\n' "$path" "$(date -Iseconds 2>/dev/null || date)"
    if [[ -r "$path" ]]; then
      cat "$path"
    elif [[ "$sudo_ready" -eq 1 ]] && sudo -n test -r "$path" 2>/dev/null; then
      sudo -n cat "$path"
    else
      printf 'status=unreadable-or-missing\n'
    fi
  } >"$file" 2>&1
}

capture_tree_values() {
  local name=$1 pattern=$2
  local file="$raw/$name.txt"
  : >"$file"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    printf '[%s]\n' "$path" >>"$file"
    if [[ -r "$path" ]]; then
      cat "$path" >>"$file" 2>&1 || :
    elif [[ "$sudo_ready" -eq 1 ]] && sudo -n test -r "$path" 2>/dev/null; then
      sudo -n cat "$path" >>"$file" 2>&1 || :
    else
      printf 'UNREADABLE\n' >>"$file"
    fi
    printf '\n' >>"$file"
  done < <(compgen -G "$pattern" || true)
}

value_or_na() {
  local path=$1
  if [[ -r "$path" ]]; then
    tr '\n' ' ' <"$path" 2>/dev/null | sed 's/[[:space:]]*$//' || printf 'NA'
  elif [[ "$sudo_ready" -eq 1 ]] && sudo -n test -r "$path" 2>/dev/null; then
    sudo -n cat "$path" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//' || printf 'NA'
  else
    printf 'NA'
  fi
}

collect_static() {
  note "Collecting identity, OS, kernel, and boot state"
  capture_shell identity 'date -Iseconds; hostname; uname -a; printf "\\n/proc/cmdline\\n"; cat /proc/cmdline 2>/dev/null; printf "\\n/proc/version\\n"; cat /proc/version 2>/dev/null; printf "\\n/uplink\\n"; uptime 2>/dev/null || true'
  capture_file os-release /etc/os-release
  capture_cmd lsb-release lsb_release -a
  capture_cmd lscpu lscpu
  capture_file cpuinfo /proc/cpuinfo
  capture_file meminfo /proc/meminfo
  capture_file vmstat /proc/vmstat
  capture_file stat /proc/stat
  capture_file interrupts /proc/interrupts
  capture_file softirqs /proc/softirqs
  capture_file modules /proc/modules
  capture_cmd lsmod lsmod
  capture_cmd ps ps axo pid,ppid,psr,stat,ni,pri,pcpu,pmem,etime,comm,args --sort=-pcpu
  capture_cmd sysctl sysctl -a
  capture_cmd dmesg dmesg --color=never
  capture_root_cmd journal-kernel journalctl -k -b --no-pager

  note "Collecting hardware inventory"
  capture_cmd lspci-nnk lspci -nnk
  capture_cmd lspci-vv lspci -vvnn
  capture_cmd lsusb-nn lsusb -nn
  capture_cmd lsusb-tree lsusb -t
  capture_cmd usb-devices usb-devices
  capture_cmd lsblk lsblk -e7 -O
  capture_cmd findmnt findmnt -A -o TARGET,SOURCE,FSTYPE,OPTIONS,VFS-OPTIONS,FS-OPTIONS
  capture_cmd mounts cat /proc/mounts
  capture_cmd dmidecode dmidecode
  capture_cmd acpidump acpidump

  note "Collecting CPU frequency and idle configuration"
  capture_cmd cpupower-frequency cpupower frequency-info
  capture_cmd cpupower-monitor cpupower monitor
  capture_cmd turbostat-version turbostat --version
  capture_cmd turbostat-snapshot turbostat --quiet --debug --interval 1 --num_iterations 1
  capture_tree_values cpufreq-policies '/sys/devices/system/cpu/cpufreq/policy*/*'
  capture_tree_values cpufreq-cpu-links '/sys/devices/system/cpu/cpu*/cpufreq/*'
  capture_tree_values cpufreq-stats '/sys/devices/system/cpu/cpu*/cpufreq/stats/*'
  capture_tree_values cpuidle '/sys/devices/system/cpu/cpu*/cpuidle/state*/*'

  note "Collecting memory, swap, and compression state"
  capture_cmd free free -h
  capture_cmd swapon swapon --show --bytes
  capture_cmd zramctl zramctl --output-all
  capture_tree_values zram-sysfs '/sys/block/zram*/**'
  capture_cmd btrfs-show btrfs filesystem show
  capture_cmd btrfs-df btrfs filesystem df /
  capture_cmd btrfs-subvolumes btrfs subvolume list /

  note "Collecting power, thermal, ACPI, and fan state"
  capture_cmd acpi acpi -V
  capture_cmd sensors sensors
  capture_cmd upower upower -d
  capture_tree_values power-supply '/sys/class/power_supply/*/*'
  capture_tree_values thermal '/sys/class/thermal/thermal_zone*/*'
  capture_tree_values hwmon '/sys/class/hwmon/hwmon*/*'
  capture_tree_values applesmc '/sys/module/applesmc/parameters/*'
  capture_tree_values backlight '/sys/class/backlight/*/*'
  capture_root_cmd vgaswitcheroo cat /sys/kernel/debug/vgaswitcheroo/switch

  note "Collecting graphics, audio, network, wireless, Bluetooth, and input"
  capture_cmd xrandr-providers xrandr --listproviders
  capture_cmd glxinfo glxinfo -B
  capture_cmd vulkaninfo vulkaninfo --summary
  capture_tree_values drm '/sys/class/drm/*/*'
  capture_cmd aplay aplay -l
  capture_cmd arecord arecord -l
  capture_cmd amixer amixer -c all scontents
  capture_cmd pactl pactl list
  capture_cmd iw-dev iw dev
  capture_cmd iw-phy iw phy
  capture_cmd rfkill rfkill list all
  capture_cmd nmcli-device nmcli -f all device status
  capture_cmd nmcli-general nmcli general status
  capture_cmd iwconfig iwconfig
  capture_cmd bluetoothctl timeout -k 2 5 bluetoothctl list
  capture_cmd btmgmt timeout -k 2 5 btmgmt info
  capture_cmd hciconfig timeout -k 2 5 hciconfig -a
  capture_cmd libinput libinput list-devices
  capture_cmd v4l2 v4l2-ctl --list-devices
  capture_cmd fwupdmgr fwupdmgr get-devices

  note "Collecting services, packages, and diagnostic tool availability"
  capture_cmd systemd-failed systemctl --failed --no-pager
  capture_cmd systemd-enabled systemctl list-unit-files --state=enabled --no-pager
  capture_cmd service-status service --status-all
  capture_cmd package-list dpkg-query -W
  capture_shell tool-versions 'for x in bash lspci lsusb cpupower turbostat sensors upower acpi iw rfkill nmcli bluetoothctl btmgmt aplay arecord pactl libinput v4l2-ctl smartctl btrfs zramctl powertop; do if command -v "$x" >/dev/null 2>&1; then printf "[%s]\\n" "$x"; "$x" --version 2>&1 | head -5; else printf "[%s] NOT INSTALLED\\n" "$x"; fi; done'

  note "Collecting storage health, module metadata, kernel config, and PCI power state"
  capture_shell block-devices 'for d in /dev/sd? /dev/nvme?n? /dev/mmcblk?; do [[ -b "$d" ]] || continue; printf "[%s]\\n" "$d"; if command -v smartctl >/dev/null 2>&1; then timeout 20 smartctl -a "$d" 2>&1 || true; else echo smartctl-not-installed; fi; done'
  capture_root_cmd pci-power bash -c 'for d in /sys/bus/pci/devices/*; do [[ -d "$d" ]] || continue; echo "[$d]"; for f in vendor device class power/control power/runtime_status power/runtime_active_time power/runtime_suspended_time; do [[ -r "$d/$f" ]] && printf "%s=%s\\n" "$f" "$(cat "$d/$f")"; done; readlink -f "$d/driver" 2>/dev/null || true; done'
  capture_shell kernel-config 'for f in /proc/config.gz "/boot/config-$(uname -r)" /usr/lib/modules/"$(uname -r)"/config; do if [[ -r "$f" ]]; then echo "[$f]"; case "$f" in *.gz) gzip -cd "$f";; *) cat "$f";; esac; fi; done'
  capture_shell module-metadata 'for m in wl b43 b43legacy brcmsmac brcmfmac nouveau snd_hda_intel snd_hda_codec_realtek snd_hda_generic snd_usb_audio applesmc apple_gmux vga_switcheroo btusb uvcvideo btrfs zram; do if command -v modinfo >/dev/null 2>&1; then echo "[$m]"; modinfo "$m" 2>&1 || true; fi; done'
  capture_shell mounts-and-acl 'findmnt -A; echo; for p in / /home /boot; do if [[ -e "$p" ]]; then printf "[%s] " "$p"; getfacl -p "$p" 2>&1 | head -30 || true; fi; done'
}

sample_interrupts() {
  awk 'BEGIN{sum=0} NR>1 {for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) sum += $i} END{print sum+0}' /proc/interrupts 2>/dev/null || printf 'NA'
}

sample_stat_field() {
  local field=$1
  awk -v f="$field" '$1 == f {print $2; found=1} END{if(!found) print "NA"}' /proc/stat 2>/dev/null
}

sample_idle_usage() {
  local total=0 path
  while IFS= read -r path; do
    [[ -r "$path" ]] || continue
    total=$((total + $(cat "$path" 2>/dev/null || printf 0)))
  done < <(compgen -G '/sys/devices/system/cpu/cpu*/cpuidle/state*/usage' || true)
  printf '%s' "$total"
}

sample_idle_time() {
  local total=0 path
  while IFS= read -r path; do
    [[ -r "$path" ]] || continue
    total=$((total + $(cat "$path" 2>/dev/null || printf 0)))
  done < <(compgen -G '/sys/devices/system/cpu/cpu*/cpuidle/state*/time' || true)
  printf '%s' "$total"
}

sample_frequency() {
  awk '
    {sum += $1; n++}
    END {if(n) printf "%.0f", sum/n; else print "NA"}
  ' < <(for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do [[ -r "$f" ]] && cat "$f"; done) 2>/dev/null
}

sample_temperature() {
  awk '
    {if($1 > max) max=$1; n++}
    END {if(n) print max; else print "NA"}
  ' < <(for f in /sys/class/thermal/thermal_zone*/temp; do [[ -r "$f" ]] && cat "$f"; done) 2>/dev/null
}

sample_power_uw() {
  local sum=0 found=0 f value current voltage
  for f in /sys/class/power_supply/BAT*/power_now; do
    [[ -r "$f" ]] || continue
    value=$(cat "$f" 2>/dev/null || printf 0)
    [[ "$value" =~ ^-?[0-9]+$ ]] || continue
    sum=$((sum + value)); found=1
  done
  if [[ "$found" -eq 1 ]]; then
    printf '%s' "$sum"
    return
  fi
  for f in /sys/class/power_supply/BAT*/current_now; do
    [[ -r "$f" ]] || continue
    current=$(cat "$f" 2>/dev/null || printf 0)
    voltage_file=${f%/current_now}/voltage_now
    voltage=$(cat "$voltage_file" 2>/dev/null || printf 0)
    if [[ "$current" =~ ^-?[0-9]+$ && "$voltage" =~ ^[0-9]+$ ]]; then
      awk -v c="$current" -v v="$voltage" 'BEGIN{printf "%.0f", (c*v)/1000000}'
      return
    fi
  done
  printf 'NA'
}

sample_loadavg() {
  awk '{print $1}' /proc/loadavg 2>/dev/null || printf 'NA'
}

write_sample_header() {
  printf '%s\n' 'timestamp,phase,battery_power_uw,interrupt_total,context_switches,processes_created,procs_running,procs_blocked,idle_entries,idle_time_us,avg_scaling_freq_khz,max_thermal_temp_mC,load1' >"$samples/samples.csv"
}

append_sample() {
  local phase=$1
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date -Iseconds 2>/dev/null || date)" \
    "$phase" \
    "$(sample_power_uw)" \
    "$(sample_interrupts)" \
    "$(sample_stat_field ctxt)" \
    "$(sample_stat_field processes)" \
    "$(sample_stat_field procs_running)" \
    "$(sample_stat_field procs_blocked)" \
    "$(sample_idle_usage)" \
    "$(sample_idle_time)" \
    "$(sample_frequency)" \
    "$(sample_temperature)" \
    "$(sample_loadavg)" >>"$samples/samples.csv"
}

run_sampling_phase() {
  local phase=$1 duration=$2
  local start end now
  start=$(date +%s)
  end=$((start + duration))
  while :; do
    now=$(date +%s)
    (( now >= end )) && break
    append_sample "$phase"
    sleep "$interval"
  done
}

run_load_phase() {
  local workers=2 pid pids=() start end load_end now phase stopped=0
  if [[ "$no_load" -eq 1 || "$load_seconds" -eq 0 ]]; then
    printf 'load_phase=skipped\n' >"$samples/load-phase.txt"
    return
  fi
  if have nproc; then
    workers=$(nproc --all 2>/dev/null || printf 2)
  fi
  (( workers > 2 )) && workers=2
  (( workers < 1 )) && workers=1
  {
    printf 'load_phase=bounded_sha256_dev_zero\nworkers=%s\nseconds=%s\n' "$workers" "$load_seconds"
    printf 'This workload reads /dev/zero, hashes in user space, and is terminated automatically.\n'
  } >"$samples/load-phase.txt"
  note "Running bounded CPU observation phase: ${workers} worker(s), ${load_seconds}s"
  for ((i=0; i<workers; i++)); do
    if [[ "$keep_workload_logs" -eq 1 ]]; then
      timeout "$((load_seconds + 3))" sha256sum /dev/zero >"$samples/workload-$i.log" 2>&1 &
    else
      timeout "$((load_seconds + 3))" sha256sum /dev/zero >/dev/null 2>&1 &
    fi
    pids+=("$!")
  done
  start=$(date +%s)
  end=$((start + sample_seconds))
  load_end=$((start + load_seconds))
  while :; do
    now=$(date +%s)
    (( now >= end )) && break
    if (( now < load_end )); then
      phase=load
    else
      phase=postload
      if [[ "$stopped" -eq 0 ]]; then
        for pid in "${pids[@]}"; do
          kill "$pid" 2>/dev/null || :
        done
        stopped=1
      fi
    fi
    append_sample "$phase"
    sleep "$interval"
  done
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || :
    wait "$pid" 2>/dev/null || :
  done
}

write_summary() {
  cat >"$out/SUMMARY.txt" <<EOF
MacBookPro5,1 hardware survey
survey_version=$SURVEY_VERSION
completed=$(date -Iseconds 2>/dev/null || date)
output=$out
sample_seconds=$sample_seconds
interval_seconds=$interval
load_seconds=$load_seconds
load_enabled=$((1 - no_load))
sudo_read_only_access=$sudo_ready
kernel=$(uname -r 2>/dev/null || printf unknown)
hostname=$(hostname 2>/dev/null || printf unknown)

The raw evidence is under raw/. Time-series readings are under samples/.
Review identifiers and MAC addresses before sharing the archive.
EOF
}

write_readme() {
  cat >"$out/README.txt" <<'EOF'
This directory was produced by mbp51-hardware-survey.sh.

The program is read-only with respect to the operating system. It collected
static hardware/configuration evidence plus bounded idle and CPU-load samples.
It did not install software, change sysctls, apply PowerTOP, switch GPUs,
suspend, reboot, or modify boot state.

Files:
  SUMMARY.txt       survey parameters and completion status
  raw/              raw command, sysfs, kernel, device, and service evidence
  samples/          samples.csv and load-phase metadata

The samples.csv columns include:
  battery power, interrupt total, context switches, process creation,
  runnable/blocked processes, CPU idle-state usage/time, current frequency,
  thermal maximum, and load average.

For comparison, run the same survey once on MX/LTS and once on each custom
kernel. Do not compare runs with different brightness, GPU state, governor,
network activity, thermal settling, or external power conditions.
EOF
}

write_sample_header
collect_static
note "Capturing idle samples for ${sample_seconds}s"
run_sampling_phase idle "$sample_seconds"
run_load_phase
write_summary
write_readme

archive="${out}.tar.gz"
if have tar; then
  tar -czf "$archive" -C "$(dirname "$out")" "$(basename "$out")" 2>/dev/null || archive=""
fi
if [[ -n "$archive" && -f "$archive" && -x "$(command -v sha256sum 2>/dev/null || true)" ]]; then
  (cd "$(dirname "$archive")" && sha256sum "$(basename "$archive")") >"$out/archive.sha256"
fi

note "Survey complete"
printf 'Evidence directory: %s\n' "$out"
[[ -n "$archive" && -f "$archive" ]] && printf 'Archive: %s\n' "$archive"
printf 'Samples: %s\n' "$samples/samples.csv"
