# BCM4322 / PCI 14e4:432b — custom-kernel Wi-Fi

## Verified build facts

GitHub Actions previously compiled Arch's `broadcom-wl-dkms` vendor source
6.30.223.271 against the then-pinned kernel 7.3.0-mbp51-extreme after
applying strict source-locked compatibility edits. The latest 7.4 development
source **must pass its own full build and DKMS run** before being treated as
compatible. A compile/link pass is not a real Wi-Fi scan/connect/resume test.

The pinned compatibility patch resolves development cfg80211 callback changes,
a removed net_device_ops ioctl hook, an obsolete global workqueue flush,
and narrowly scoped old-driver warnings. It fails if the expected source
structure changes or if the exact pinned upstream SHA/release isn't matched.

## Installable compatibility, without public proprietary redistribution

`compat/broadcom/build-on-device.sh` compiles patched `wl.ko` from a private
copy of Arch's installed `/usr/src/broadcom-wl-6.30.223.271`. It does not
change the Arch-maintained source, stock modules or loaded driver.

`compat/broadcom/make-local-package.sh KERNELRELEASE` then produces
`mbp51-broadcom-wl-<ABI>-1-x86_64.pkg.tar.zst`. Pacman manages installation
and removal of `/usr/lib/modules/KERNELRELEASE/updates/mbp51/wl.ko`.
The package is built and retained **on the machine**, not uploaded to a
public GitHub artifact. It is kernel-version-specific, **not DKMS-managed**.

The standalone Broadcom CI workflow downloads the *matching* kernel/headers
artifact, builds the maintained Arch sources with our pinned patch, verifies
`wl.ko` vermagic, and now tests building/inspecting the local pacman package.
Its public diagnostic artifact contains logs and checksums, **not wl.ko**.

Recent successful hosted evidence for the pinned source and isolated tiers:

- Legacy/Daily baseline compatibility: run `40247554764` succeeded on commit
  `23c8b461`.
- BORE compatibility: run `40265566020` succeeded on commit `4a1d4442`.
- Extreme Lab compatibility: run `40265593461` succeeded on commit
  `4a1d4442`.
- A second successful tier compatibility run, `40265636808`, also completed
  on commit `4a1d4442`.

These are compile, link, vermagic, and local-package checks. They do not
replace a physical Wi-Fi association, suspend/reconnect, or boot test.

Follow [installation/recovery](INSTALL.md). Never replace or remove the working
stock kernel's Wi-Fi module to make the custom kernel load.

## On-device Wi-Fi acceptance

With wired Ethernet/USB network fallback and a stock boot entry:
verify `lspci -nn -d 14e4:` for `14e4:432b`, inspect `modinfo -k
KERNELRELEASE -n wl`, confirm `lsmod` shows wl rather than colliding
b43/ssb/bcma, scan using `nmcli device wifi list --rescan yes`, associate
to a WPA2 AP, and test reconnect after manual suspend and lid wake. Include
2.4 and 5 GHz as supported by the physical card; do not promise WPA3.

Upstream b43 supports some BCM4322 functions only partially and is disabled
in this intentionally wl-first kernel. Enabling it would require a reviewed
kernel change, firmware and a separate hardware acceptance test.
