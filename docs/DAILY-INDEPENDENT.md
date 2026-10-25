# Independent Daily kernel (first of three tiers)

This is an isolated Tier 1 build contract, NOT an assertion that it is
already compiled or physically validated. BORE and Lab deliberately fail
closed until real, reviewed scheduler/voltage patchsets exist.

## Architecture

`MBP51_TIER=daily` selects:
- pkgbase `linux-mbp51-daily` and matching `linux-mbp51-daily-headers`;
- release `7.3.0-mbp51-daily-g21a7f44f-v1`;
- separate artifact directory `dist/daily`;
- private local-only `mbp51-broadcom-wl-daily` depending on the Daily kernel;
- boot path `/boot/mbp51/daily`;
- GRUB script `/etc/grub.d/42_mbp51-daily`.

The legacy mode remains the default in all existing scripts and preserves the
current v2 `linux-mbp51-extreme` and localversion semantics. No existing
kernel, boot file, or external module is replaced by Daily.

CI first validates lint, profile isolation, and Kconfig. GitHub Actions then
builds a kernel and headers together. Never install the new kernel until
binary compilation and checksum-verification have passed.

## Install (only after published verified Daily artifacts exist)

Download the `mbp51-daily-kernel-and-headers` artifact from the
Build independent MacBookPro5,1 Daily kernel GitHub workflow. Extract its
contents directly into `dist/daily` in the cloned repository.

```bash
git fetch origin main
git switch main && git pull --ff-only
bash install/activate-daily-kernel.sh --plan dist/daily
bash install/activate-daily-kernel.sh --install dist/daily
```

The installer first checks source/release/artifact hashes, matching LTS
recovery files, the explicit LTS GRUB default, Btrfs/EFI layout, and DMI.
After installing the Daily binary and headers, it privately builds and
installs the matched Broadcom BCM4322 `wl.ko` using the installed Arch
broadcom-wl-dkms source. No vendor module is published on GitHub. It
generates a host-only initramfs and a generic fallback and adds Daily
menu entries without changing the legacy menu or LTS default.

Boot by manually selecting Daily in GRUB. Validate Wi-Fi, Realtek HDA
audio, UPower, BAT* battery, Nouveau renderer offload, gmux, Bluetooth,
Btrfs ACL, sleep/wake, thermals and Xorg DRM warnings before promoting
it. Compare against a read-only stock-LTS reference from
`scripts/compare-kernels.sh`.

## Tier roadmap

BORE is NOT equivalent to just reusing Daily packages under a different
name. Port and audit the 7.3-rc2 BORE 7.0.0 patch to our exact pinned
development commit, preserve runtime toggling and run scheduler latency
benchmarks. Extreme needs a separate verified voltage-control experiment
and explicit stock-VID fallback. Do not silently publish mock tiers.
