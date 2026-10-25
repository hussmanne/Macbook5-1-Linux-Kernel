# Broadcom BCM4322 / 14e4:432b qualification

## Driver decision

Primary driver is the official Arch Extra **broadcom-wl-dkms** package, not an
untracked binary shim. Its version changes with the Arch package repository.
The release's original driver is 6.30.223.271 with distribution patches.

The PCI ID 14e4:432b has **partial** upstream b43 support, requiring nonfree
firmware and with important 802.11n limitations. This kernel deliberately
currently excludes b43, so b43 cannot be used as a fallback with the existing
binary artifact. No automatic driver substitution has been authorized.

## Automated CI validation

The separate `.github/workflows/broadcom-compatibility.yml` GitHub Actions
workflow runs after each successful kernel build and can be launched manually
against a selected existing successful Actions run. It downloads the exactly
matching kernel + headers, checks provenance/hashes, installs the headers
inside ephemeral Arch, builds the official patched `broadcom-wl-dkms` driver,
and checks `wl.ko` and vermagic. Failure logs are kept in a separate
diagnostic artifact.

The test does **not** establish runtime compatibility, loading, network scans,
network association, 2.4/5 GHz support, WPA2 authentication, or resume health.

The first build check found API mismatches (cfg80211 key callbacks, removed
ndo_do_ioctl), an isprint macro collision and old driver warnings. The pinned
kernel identifies as 7.3.0 despite containing 7.4-era APIs. The strictly
source-locked scripts/patch-broadcom-wl.py adapts only ephemeral Arch driver
sources in CI and fails on unexpected source layouts. Only two specific
legacy warning categories are made nonfatal; actual API errors remain fatal.

If the driver fails to compile, first inspect `wl-make.log` and compare any
new kernel APIs to the latest maintained Arch/Debian patch set. Do not suppress
compile errors, disable warnings globally, or insert unsupported kernel stubs.
If all maintained patches fail, propose a minimal, source-documented patch and
test it on CI before considering a driver fork.

## Real-hardware checklist (only after packages and recovery route are ready)

With wired fallback available and stock kernel selectable:

1. Verify `lspci -nn -d 14e4:` reports BCM4322 `14e4:432b` and inspect
   `lsmod` to confirm `wl` rather than colliding `b43`, `ssb`, `bcma`.
2. Confirm DKMS install, `modinfo wl` vermagic, `dmesg` for firmware/driver
   messages, `nmcli device wifi list --rescan yes` and actual WPA2 connection.
3. Test a reconnect after `systemctl suspend` and after resuming from lid
   closure; verify no permanent RF-kill and check `journalctl -k -b`.
4. Evaluate 2.4 GHz / 5 GHz APs, signal, throughput and idle power.
5. Do not assert WPA3 connectivity for this 2008-era chipset.

Wired forcedeth Ethernet or supported USB networking is the recovery path if
`wl` fails. Do not remove the stock kernel or its headers until qualified.
