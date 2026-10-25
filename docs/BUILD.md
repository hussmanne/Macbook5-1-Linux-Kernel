# GitHub Actions build instructions

1. The source SHA is fixed in ../source.lock; changing it requires review.
2. Pull requests run static bash/source-lock validation only; merge to main triggers a full build.
3. Merging to main launches the full kernel build. You may rerun manually via
   GitHub Actions > Build experimental MBP5,1 kernel > Run workflow.
   No local WSL, macOS or Windows compiler required.
4. Build job frees runner disk space, launches Arch Linux base-devel Docker,
   installs compiler/kernel dependencies, runs unprivileged scripts/build.sh.
5. The build extracts a pinned upstream source archive, runs x86_64_defconfig,
   applies scripts/configure.sh, resolves dependencies with make olddefconfig,
   checks final .config with scripts/audit-config.sh, then invokes upstream
   make pacman-pkg with only kernel and headers requested.
6. Successful artifacts include kernel package, headers package, source SHA,
   tarball SHA256, resulting kernelrelease, resolved .config, compiler/version
   manifest, runtime-config archive and package hashes.

The pinned source currently has Makefile VERSION=7, PATCHLEVEL=3, SUBLEVEL=0,
even though it is the development tree for the next version. Do not invent 7.4
release-version packaging or claim merged patches absent from the source.

The first hosted build may fail on upstream Kconfig churn, packaging assumptions,
Arch package dependencies, or the 14 GB runner disk. Inspect exact failure
and correct the code/config; do not weaken mandatory device/security audits.

The workflows do not install the kernel, sign the packages, claim wl DKMS
compatibility, or certify real battery/graphics behavior. Before trusting
downloaded unsigned public artifacts, verify checksums from the build you ran.
The cloud builder cannot reach the MacBook's hardware.

For local development, an x86-64 Arch environment with base-devel and
the documented build dependencies can run scripts/build.sh as an unprivileged
user, but this is optional.
