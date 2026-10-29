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

That sentence is weaker than the code. Verified against the pinned source and
the resolved configuration, `CONFIG_SCHED_BORE=y` changes EEVDF *regardless of
the runtime key*:

| Scheduler property | Daily (EEVDF) | BORE build at `sched_bore=0` |
|---|---|---|
| `sysctl_sched_tunable_scaling` | `LOG` (factor 2 on 2 CPUs) | `NONE` (factor 1) |
| request size `sysctl_sched_base_slice` | 1.4 ms | 2.0 ms (`nsecs_per_tick * ceil(min_base_slice / nsecs_per_tick)`) |
| `set_protect_slice()` window | 0.7 ms (`normalized_…`) | 2.0 ms |
| `sched_update_scaling()` | present | compiled out |

So `sched_bore=0` is **not** an EEVDF-equivalent control arm. It is a BORE
build with the burst heuristic off. Two consequences:

1. Daily-vs-BORE(0) differences cannot be attributed to burst prioritisation.
2. At HZ=1000 the BORE slice formula is quantised to whole ticks (1, 2, 3 ms),
   so a 1.4 ms slice match is impossible. The closest achievable arm is
   `sched_min_base_slice=1000000` (1 ms request / 1 ms protection), set at boot
   through the `sched_min_base_slice` debugfs/sysctl control rather than a
   rebuild.

### Corrected comparison protocol

Measure these three, in this order, with identical governor, power profile,
GPU state, thermal settling and workload:

1. **Daily** (EEVDF, 1.4 ms / 0.7 ms) — the reference.
2. **BORE with `kernel.sched_bore=0` and min base slice forced to 1 ms** — the
   BORE build's closest approach to EEVDF; use it to quantify how much of any
   difference comes from slice constants rather than burst logic.
3. **BORE with `kernel.sched_bore=1`** — the feature under test.

If a future revision wants a true control, gate the `SCHED_TUNABLESCALING` and
base-slice hunks on the same static key so that `sched_bore=0` restores EEVDF's
constants. That is a source change and must go through the normal locked-patch
review, not a runtime tweak.

The patch applies cleanly with `git apply --check --whitespace=error` to the
exact pinned source. The patch and its SHA-256 are locked in
`patches/bore.lock`.

## Package and boot isolation

```text
package: linux-mbp51-bore
release: 7.3.0-mbp51-bore-g21a7f44f-bore7.0.0-r1-c2-c2
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
