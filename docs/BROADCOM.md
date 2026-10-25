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
source-locked compat/broadcom/patch-broadcom-wl.py adapts only ephemeral Arch driver
sources in CI and fails on unexpected source layouts. Only two specific
legacy warning categories are made nonfatal; actual API errors remain fatal.

If the driver fails to compile, first inspect `wl-make.log` and compare any
new kernel APIs to the latest maintained Arch/Debian patch set. Do not suppress
compile errors, disable warnings globally, or insert unsupported kernel stubs.
If all maintained patches fail, propose a minimal, source-documented patch and
test it on CI before considering a driver fork.

## Local build without damaging the stock recovery kernel

The CI compatibility script patches Arch `broadcom-wl-dkms` **in an ephemeral
container**, so installing the ordinary unpatched package on the MacBook
does not automatically provide compatible `wl.ko` for this custom kernel.

A separate **unprivileged, build-only** helper now reproduces the patch/build
locally in an isolated copy. It does not edit `/usr/src`, the current Arch
driver, the bootloader, or any loaded module:

```bash
# Boot the STOCK working kernel. Install matching custom kernel headers first.
# Ensure base-devel, python, kmod and broadcom-wl-dkms are installed.
bash compat/broadcom/build-on-device.sh 7.3.0-mbp51-extreme
```

Successful output is under
`.work/broadcom/7.3.0-mbp51-extreme/wl.ko` with SHA256, build log,
source-patch manifest and vermagic. This keeps the original DKMS source
unmodified, so later attempts to rebuild against the stock kernel still use
Arch's normal patches.

**Do not copy the resulting module into the custom kernel automatically.**
Once the custom kernel packages and matching headers have been installed
without replacing the stock kernel, after reviewing the module provenance
and checksums, installation of this *locally built* module may be done by
an administrator while still booted on the known-working stock kernel:

```bash
K=7.3.0-mbp51-extreme
(cd ".work/broadcom/$K" && sha256sum -c wl.ko.sha256)
sudo install -Dm644 ".work/broadcom/$K/wl.ko" \
  "/usr/lib/modules/$K/updates/mbp51/wl.ko"
sudo depmod -a "$K"
modinfo -k "$K" -F vermagic wl
```

Keep working wired networking and recovery boot media; **do not try to
modprobe this module into the running stock kernel**. If the custom kernel
fails to load it, select the stock kernel and remove only the custom
`/usr/lib/modules/$K/updates/mbp51/wl.ko`, then run `depmod -a "$K"`.
This manually installed module is not DKMS-managed: rebuild after custom
kernel/header updates, and verify again after Arch package upgrades.

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
