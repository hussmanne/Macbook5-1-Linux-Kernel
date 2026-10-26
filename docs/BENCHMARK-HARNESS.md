# MacBookPro5,1 benchmark harness

The scripts under `scripts/benchmark/` collect evidence on the physical
MacBook. They are intentionally read-only: they do not change GRUB, kernels,
PowerTOP policy, GPU rails, governors, or suspend state.

## Capture

```bash
bash scripts/benchmark/baseline.sh "$HOME/mbp51-bench/lts-idle" 5 5
bash scripts/benchmark/ui-load.sh "$HOME/mbp51-bench/lts-ui" 30 2
bash scripts/benchmark/validate.sh "$HOME/mbp51-bench/lts-ui"
```

`baseline.sh` records immutable kernel/config/source identity where available,
AC/battery state, governor and frequency limits, PCI/module/service snapshots,
thermal/fan readings, CPU idle residency, memory PSI, context switches and
power-supply telemetry.

`ui-load.sh` runs two bounded CPU workers and measures a foreground timer
overshoot distribution, reporting p50/p95/p99. This is a scheduler/wakeup
responsiveness proxy, **not** a browser paint or human input-latency result.
Use the same duration, worker count, display session, AC/battery state and
thermal settling procedure for both kernels. Browser scrolling, audio, Wi-Fi,
Bluetooth and suspend/resume remain separate physical qualification tests.

## Compare

```bash
bash scripts/benchmark/compare.sh \
  "$HOME/mbp51-bench/lts-ui" \
  "$HOME/mbp51-bench/daily-ui" \
  "$HOME/mbp51-bench/daily-vs-lts.txt"
```

The generated report shows identity fields and percentile deltas, but it does
not declare an optimization successful. Record one variable at a time and
label the result `KEEP`, `REVERT`, or `NEEDS EVIDENCE` after checking thermal
soak, workload variance and physical hardware behavior.
