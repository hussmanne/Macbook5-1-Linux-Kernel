# Memory, swap and compressed RAM (2026-10-29)

Answers, for this machine: what swap exists, what format it is, and whether the
compressed-RAM settings are right. Same labels as
[REVIEW-2026-10-29.md](REVIEW-2026-10-29.md): **[measured]**, **[inferred]**,
**[estimate]**.

---

## 1. What is configured today

| Layer | Setting | Where |
|---|---|---|
| Kernel | `ZRAM=m`, `ZRAM_BACKEND_LZ4=y`, `ZRAM_DEF_COMP="lz4"` | `scripts/configure.sh` |
| Kernel | `ZRAM_BACKEND_LZO` **off**, `ZSWAP` **off**, `SWAP=y` | `scripts/configure.sh`, `audit-config.sh` |
| Kernel | `CPU_MITIGATIONS=n`, `HIBERNATION` **off** | `scripts/configure.sh` |
| zram device | `zram-size = min(ram / 2, 4096)` → **4 GiB logical** at 8 GiB RAM | `runtime/systemd/zram-generator.conf` |
| zram device | `compression-algorithm = lz4`, `swap-priority = 100` | same |
| VM | `vm.swappiness = 100`, `vm.page-cluster = 0` | `runtime/sysctl.d/99-mbp51-memory.conf` |
| Btrfs | `noatime,compress=zstd:1`, subvolumes `@`, `@home`, `@snapshots` | `install/archiso-install.sh` |

**[measured]** There is **no disk swap anywhere in this repository**: nothing in
`install/`, `iso/` or `scripts/` runs `mkswap`, `swapon` or writes a swap entry
to `/etc/fstab`. A clean install from `install/archiso-install.sh` ends up with
**zram only**.

**[measured]** The machine itself currently has more than that:
`LOCAL-MODEL-HANDOFF.md` (a measured snapshot of the physical machine, not a
plan) records *"4 GiB LZ4 ZRAM high-priority swap, ~8.8 GiB SSD swap
fallback"*. That fallback came from the **previous** install, not from this
repo. Reinstalling with this repo's installer silently loses it.

That is the single most important sentence in this document.

---

## 2. How zram actually works (what "4 GiB" means)

**[inferred]** `zram-size` is the size of the *block device*, i.e. the logical
swap capacity — not the RAM it occupies. RAM is consumed only as pages are
written to it, at the compression ratio. At the usual 2.2–2.5× for desktop
pages under LZ4:

- 4 GiB logical swap costs roughly **1.6–1.8 GiB of physical RAM** when full.
- An 8 GiB machine therefore gets ~4 GiB extra effective memory at full
  occupancy, and pays nothing at all when unused.

zram is a **block device**, not a file and not a filesystem. Its "format" is
swap space: `mkswap /dev/zram0`. There is no file to fragment, no allocator in
the path, and no I/O — which is exactly why it is the right first swap tier on
a 2009 laptop with a SATA SSD.

**[inferred]** `vm.swappiness = 100` is correct *for zram*, and would be wrong
for a disk-only machine: it tells the kernel to prefer compressing anonymous
pages into RAM rather than dropping page cache. `vm.page-cluster = 0` is also
correct — swap readahead of one page, because decompression is cheap and
speculative readahead of neighbouring pages is wasted work.

**[inferred]** Two settings from the standard zram tuning are missing from
`99-mbp51-memory.conf` and are added by this change:

```
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
```

They stop the allocator from aggressively reclaiming and boosting watermarks
while zram is holding a large fraction of RAM, which is where the visible
stalls under memory pressure come from. **[estimate]** No measurable power
effect; this is a latency/stall setting.

---

## 3. The compressor choice — and an error in our own documentation

**[measured]** Upstream `drivers/block/zram/Kconfig` at the pin:

- Backends are separate symbols: `ZRAM_BACKEND_LZ4`, `_LZO`, `_ZSTD`,
  `_DEFLATE`, `_842`, `_LZ4HC`.
- The `choice` for the default has **`default ZRAM_DEF_COMP_LZORLE`** — upstream
  ships `lzo-rle` as the default, not `lz4`.

**[measured]** `docs/ENGINEERING.md` claims the first build *"incorrectly forced
LZO-RLE, which would reject the requested LZ4 userspace setting"*. **That
mechanism is wrong.** In `zram_drv.c`:

- `default_compressor = CONFIG_ZRAM_DEF_COMP` is only the *initial* value.
- `comp_algorithm_store()` → `zcomp_lookup_backend_name(buf)`; it accepts
  **any backend that was compiled in**, and fails with `-EINVAL` only when the
  backend is absent.

So a tree with `ZRAM_BACKEND_LZ4=y` accepts `compression-algorithm = lz4`
regardless of which compressor is the compile-time default. What actually
matters is the set of **backends**, not the default. The correction is applied
to `ENGINEERING.md` with this change.

The practical consequence: `no ZRAM_BACKEND_LZO` in `configure.sh` was
justified by a mechanism that does not exist, and it forecloses `lzo-rle` as a
runtime experiment for no stated benefit.

| Compressor | Ratio [estimate] | CPU on a 2.4 GHz Penryn | Available now |
|---|---|---|---|
| `lz4` | ~2.2× | lowest | **yes** (current default) |
| `lzo-rle` | ~2.4×, RLE fast path for zero pages | similar to lz4 | no — backend compiled out |
| `zstd` | ~2.9× | 2–4× slower | no — backend compiled out |

**[estimate]** `lz4` is a defensible choice for this CPU, and it is the right
default when the goal is latency and power rather than maximum memory. But
`lzo-rle` would plausibly buy 5–15 % more effective swap for about the same
CPU, and nobody can test that today because the backend is not built.

Recommendation: enable `ZRAM_BACKEND_LZO` (and optionally `ZRAM_BACKEND_ZSTD`)
in a future `c3`, keep `lz4` as the default, and let the algorithm be a runtime
A/B — the same pattern already used for the idle governor, where both `menu`
and `teo` are built and the choice is a boot parameter. **[estimate]** A few
tens of KiB of image, zero runtime cost while unused. Not worth a rebuild on
its own.

---

## 4. Disk swap: three options, in order of increasing disruption

### 4.1 Nothing (current repo behaviour)

zram only. Defensible: 8 GiB RAM plus 4 GiB compressed swap covers normal
desktop use, and it is what Fedora and Arch's default zram setup do. The cost
is that when the logical 4 GiB fills there is no overflow — the kernel goes
straight to the OOM killer instead of degrading slowly.

### 4.2 A swapfile on Btrfs — the constraint list comes from the kernel

**[measured]** `fs/btrfs/inode.c::btrfs_swap_activate()` refuses a swapfile
unless all of these hold. These are the kernel's own messages:

```
swapfile must not be compressed
swapfile must not be copy-on-write
swapfile must not be checksummed
swapfile must not have holes
swapfile must not be inline
swapfile must have single data profile
swapfile must be on one device
cannot activate swapfile while exclusive operation is running
cannot activate swapfile because snapshot creation is in progress
```

In practice that means:

- **`chattr +C` must be set on an empty file, before any data is written.**
  `+C` implies both NOCOW and NODATASUM, so one attribute satisfies the first
  three conditions. Setting it after `fallocate` is the classic mistake and
  leaves the extents copy-on-write.
- **`fallocate`, not `dd`**, so the file is fully allocated and has no holes.
- **Single-device Btrfs with a single data profile.** A single-disk install is
  fine; do not do this on a `raid0`/`raid1` filesystem.
- **No concurrent balance, device add/remove or resize** while swap is active.

The procedure, on this layout:

```sh
# On the subvolume that will hold it (see the snapshot warning below).
sudo truncate -s 0 /swapfile          # empty first
sudo chattr +C /swapfile              # NOCOW + NODATASUM, before any write
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon -p 10 /swapfile           # priority 10: below zram's 100

# Persist. pri=10 keeps zram first; the file is only reached when zram is full.
echo '/swapfile none swap defaults,pri=10 0 0' | sudo tee -a /etc/fstab
```

Verify with `lsattr /swapfile` (must show `C`), `swapon --show`, and
`filefrag -v /swapfile` (should be one extent).

**The snapshot interaction is the non-obvious part.** `btrfs_swap_activate()`
takes `btrfs_drew_try_write_lock(&root->snapshot_lock)`: while a swapfile on a
subvolume is active, **taking a snapshot of that subvolume fails with
`EBUSY`**. This repository's installer creates `@snapshots` and mounts it at
`/.snapshots`, so a snapshot workflow is clearly intended. Two ways to keep
both:

- put the swapfile on a subvolume you do not snapshot (`@home`, or a dedicated
  `@swap` mounted at `/swap`), or
- accept that `@` cannot be snapshotted while swap is on — which is almost
  certainly not what you want.

`chattr +C` overrides the `compress=zstd:1` mount option for that one file, so
the installer's mount options do not need to change.

### 4.3 A swap partition

**[inferred]** A swap partition has **none** of the constraints above: no COW,
no compression, no snapshots, no `resume_offset` arithmetic. If the disk is
ever repartitioned — at the next clean install, not now — this is the better
answer for a Btrfs machine, and it is the only tidy route to hibernation.

It is also the only one of the three that is destructive to set up, which puts
it outside this repository's standing rule against automated disk operations.

---

## 5. Hibernation

**[measured]** `CONFIG_HIBERNATION` is **off**, deliberately. Worth knowing
what turning it on would actually require, because it changes the sizing answer
completely:

- **zram cannot hibernate.** Hibernation writes RAM to a persistent device;
  zram lives in RAM. A disk swap of **at least RAM size (8 GiB+)** is
  mandatory.
- The bootloader needs `resume=<device>` and, for a swapfile,
  `resume_offset=<physical offset>`, obtained with
  `btrfs inspect-internal map-swapfile -r /swapfile`.
- On Btrfs the swapfile must be reachable before the root filesystem is
  mounted, which is why the offset is physical and why the swapfile cannot be
  on a subvolume that is moved or balanced.

**[estimate]** For a laptop that suspends to RAM in about a second, hibernation
buys one thing: a session that survives a flat battery. That is a real benefit
and a real cost (8 GiB of SSD, a bootloader parameter that can brick a resume
if wrong). Not recommended unless the machine is actually losing sessions.

---

## 6. Recommended settings for this machine

Keep, and do not change:

- `zram-size = min(ram / 2, 4096)`, `swap-priority = 100`, `lz4`
- `vm.swappiness = 100`, `vm.page-cluster = 0`

Add (this change):

- `vm.watermark_boost_factor = 0`, `vm.watermark_scale_factor = 125`

Optional, if OOM kills become real:

- a 4 GiB Btrfs swapfile at `pri=10` on a **non-snapshotted** subvolume, per
  §4.2

Defer to a future config revision:

- `ZRAM_BACKEND_LZO=y` (+ `ZRAM_BACKEND_ZSTD=y`), keeping `lz4` as the default,
  so the compressor becomes a runtime experiment rather than a rebuild

Not recommended unless sessions are being lost:

- hibernation, which forces an 8 GiB disk swap and a `resume_offset`

---

## 7. What to measure

All of it is one command on the machine:

```sh
swapon --show                       # priorities, sizes, zram present?
zramctl                             # algorithm, logical size, DATA vs COMPR
cat /proc/meminfo | grep -i swap
cat /sys/block/zram0/comp_algorithm # *lz4 means selected; the list is available
```

`scripts/postboot-check.sh` already reports `swapon --show=NAME,ALGORITHM`, and
`scripts/hardware-report.sh` captures `swapon --show`, so the physical state is
already part of the acceptance record. `zramctl`'s `DATA`/`COMPR` columns are
the honest ratio measurement, and they are the number to compare if the
compressor is ever changed.
