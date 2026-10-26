# One-command MX Linux hardware survey

`tools/mbp51-hardware-survey.sh` is a portable, read-only evidence collector
for the MacBookPro5,1. It is designed to be downloaded as a GitHub Actions
artifact and run on the currently installed MX Linux system before changing
the kernel.

## What it collects

The program captures both normalized samples and raw evidence for:

- OS, kernel, boot command line, DMI, CPU model/features, and process state;
- PCI, USB, storage, ACPI, firmware, drivers, and module metadata;
- CPUFreq policy, governor, limits, available frequencies, transition stats;
- CPU idle states, usage, residency time, rejection counters, and C-state data;
- interrupts, softirqs, context switches, process creation, runnable tasks;
- battery/AC power-supply attributes, discharge power, voltage/current/capacity;
- thermal zones, hwmon values, Apple SMC parameters, fans, and backlight;
- graphics, DRM, Nouveau, gmux, vga_switcheroo, Xrandr, and GL information;
- HDA/USB audio, ALSA/PulseAudio state, Wi-Fi, rfkill, NetworkManager;
- bounded Bluetooth queries, Apple input, camera, FireWire, and services;
- memory, swap, ZRAM, Btrfs, mounts, ACLs, SMART data, and kernel config;
- a controlled idle observation phase and a bounded two-worker hash-load phase.

It does not install packages, alter sysctls, invoke PowerTOP auto-tune, switch
GPUs, suspend, reboot, touch GRUB, or modify kernel state. It requests one
optional `sudo` authentication so read-only PCI/debug/kernel data can be
captured; `--no-sudo` disables that request.

## GitHub Actions download

Run the workflow:

```text
Actions → Package MX hardware survey → Run workflow
```

Download the artifact named:

```text
mbp51-hardware-survey
```

Extract it on MX. The bundle contains an executable `mbp51-hardware-survey.sh`
and this documentation. Run the program from a terminal; the only expected
interaction is the optional sudo password prompt.

## Safe default run

```bash
./mbp51-hardware-survey.sh
```

It creates:

```text
~/mbp51-survey-YYYYMMDD-HHMMSS/
~/mbp51-survey-YYYYMMDD-HHMMSS.tar.gz
```

The result contains:

- `SUMMARY.txt` — run parameters and completion status;
- `raw/` — raw command and sysfs evidence;
- `samples/samples.csv` — time-series power, interrupt, idle, frequency,
  thermal, and load readings;
- `samples/load-phase.txt` — exact controlled workload description;
- `README.txt` — interpretation notes.

## Options

```text
--seconds N       idle/load phase length; default 30
--interval N      sample spacing; default 2
--load-seconds N  bounded CPU workload length; default 15
--no-load         collect static/idle evidence only
--no-sudo         do not request read-only sudo access
--keep-workload   retain temporary workload logs
--output DIR      choose output directory
```

For the first MX baseline, use the safe default. If the laptop is thermally
unstable or running on a weak battery, use `--no-load`; no data is worth
overheating the machine.

## How to use the evidence

Run the same program on:

1. current MX Linux;
2. Linux LTS;
3. Daily/BORE-capable with BORE disabled;
4. Daily/BORE-capable with BORE enabled;
5. Extreme Lab.

Keep brightness, AC/battery state, screen/session, network traffic, GPU mode,
governor, thermal settling, and sample options fixed. The CSV lets us compare:

- battery discharge power when `power_now` or current/voltage exists;
- interrupt growth and approximate wakeup activity;
- C-state/idle-state entry and residency growth;
- CPU frequency response during idle and controlled load;
- process scheduling activity and thermal response.

The raw directory is intentionally retained so missing tools or unusual MX
hardware can be diagnosed without asking you to rerun individual commands.
Review serial numbers and MAC addresses before sharing the archive.
