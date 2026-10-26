# Independent BORE kernel

BORE is a real, separately packaged scheduler alternative to the Daily
upstream-EEVDF kernel. It is not substituted into Daily and it is not a fake
menu entry.

## Provenance

- Linux source: `21a7f44fd0765fcc5194130b28767786eba1d1e7`
- Upstream BORE lineage: `firelzrd/bore-scheduler`, commit
  `1e2f57ad74e8b8b1d315c03b7abd8d74e40448b4`
- Upstream patch lineage: `8e0f25bdcc68fa437072260acc6b4347ece2a794`
- Local port: `patches/bore/0001-bore-7.0.0-linux7.3-rc2.patch`
- Local patch revision: `bore7.0.0-r1`

The local port makes two deliberate surgical changes required by this tree and
project policy:

1. Futex wait handling uses the pinned kernel's
   `hrtimer_sleeper_task_get()` accessor.
2. BORE is compiled in but starts disabled: the Kconfig default, runtime
   sysctl, and static key are all default-off. The physical test can enable it
   with `kernel.sched_bore=1` and return to `0` without changing kernels.

`kernel.sched_bore=0` disables the BORE static-key mechanism, but the BORE
variant still carries its compile-time base-slice/scaling code. It must be
measured against Daily EEVDF; it is not claimed to be byte-identical to Daily.

The patch applies cleanly with `git apply --check --whitespace=error` to the
exact pinned source. The patch and its SHA-256 are locked in
`patches/bore.lock`.

## Package and boot isolation

```text
package: linux-mbp51-bore
release: 7.3.0-mbp51-bore-g21a7f44f-bore7.0.0-r1
headers: linux-mbp51-bore-headers
Broadcom: mbp51-broadcom-wl-bore
boot: /boot/mbp51/bore/
GRUB: mbp51-bore / mbp51-bore-fallback
```

Build and verify in CI first. The BORE workflow is
`.github/workflows/build-bore.yml`.

## Build and plan

```bash
MBP51_TIER=bore bash scripts/check-kconfig.sh
MBP51_TIER=bore bash scripts/test-verify-artifacts.sh
bash install/activate-bore-kernel.sh --plan dist/bore
```

The installer keeps Linux LTS as the explicit default, leaves the legacy
`/boot/mbp51/` files untouched, creates host-only and generic Dracut images,
and requires the exact matching private Broadcom module before installation.

## Qualification status

The source-port, artifact, kernel-build, and matching Broadcom gates have
passed in GitHub Actions for commit `4a1d4442`. No physical MacBook boot or
scheduler performance claim has been made yet.

On the physical machine, compare three states with the same HZ, governor,
power profile, GPU state, workload, and thermal settling:

1. Daily upstream EEVDF.
2. BORE kernel with `kernel.sched_bore=0`.
3. BORE kernel with `kernel.sched_bore=1`.

Record p50/p95/p99 foreground latency proxy, throughput, context switches,
memory PSI, C-state residency, temperatures, fan behavior, and power. Do not
call BORE an improvement without repeatable before/after evidence.
