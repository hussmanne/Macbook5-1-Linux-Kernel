#!/usr/bin/env bash
# Read-only GPU qualification. NEVER power off or switch a GPU automatically.
set -uo pipefail
echo '== Kernel =='
uname -r
echo '== GPU PCI IDs/drivers =='
lspci -nnk | grep -A4 -E 'VGA compatible controller|3D controller'
echo '== X11 providers =='
if command -v xrandr >/dev/null; then timeout 8 xrandr --listproviders || :; fi
echo '== DRM nodes =='
ls -l /dev/dri/ 2>&1 || :
echo '== GPU PCI power =='
for id in 0000:02:00.0 0000:03:00.0; do
  dir="/sys/bus/pci/devices/$id"
  echo "$id"
  for key in power/control power/runtime_status power/runtime_suspended_time power/runtime_active_time; do
    [[ -r "$dir/$key" ]] && echo "$key=$(cat "$dir/$key")"
  done
done
echo '== VGA switcheroo =='
if [[ -r /sys/kernel/debug/vgaswitcheroo/switch ]]; then
  timeout 5 cat /sys/kernel/debug/vgaswitcheroo/switch || :
elif sudo -n true 2>/dev/null; then
  timeout 5 sudo -n cat /sys/kernel/debug/vgaswitcheroo/switch || :
else
  echo 'Run sudo -v then repeat for privileged switcheroo status.'
fi
echo '== GL renderers (optional) =='
if command -v glxinfo >/dev/null; then
  timeout 8 glxinfo -B | grep -E 'OpenGL renderer|OpenGL version' || :
  timeout 8 env DRI_PRIME=1 glxinfo -B | grep -E 'OpenGL renderer|OpenGL version' || :
else echo 'glxinfo unavailable'; fi
