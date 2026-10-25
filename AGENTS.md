# Repository agent contract

Read docs/ENGINEERING.md and source.lock before any change.

1. This is a fixed-device MacBookPro5,1 Linux project, not a generic kernel.
2. Preserve user decisions: compiled-out CPU mitigations, global PowerTOP
   auto-tune, and one combined extreme custom kernel.
3. No false provenance: source.lock pins an immutable upstream commit. At
   present the Linux Makefile still reports 7.3.0. Do not label it released
   Linux 7.4, or invent CachyOS patches or performance claims.
4. Do not silently relax Kconfig audit or remove essential gmux/Nouveau,
   Apple SMC/input, AHCI, ACPI S3, module loading, firmware, DEBUG_FS,
   PERF_EVENTS, or networking support to obtain a green build.
5. Use upstream pacman-pkg packaging and its install-extmod-build helper.
   Do not claim the separate headers package supports Broadcom wl DKMS
   until its module build is actually checked.
6. Preserve stock kernel and recoverable bootloader path. Never automate
   installation onto the MacBook from GitHub CI.
7. Public repository: no privileged pull_request_target, no write tokens
   for untrusted changes, no automatic production publishing or merging.
   Full kernel builds run only for trusted main-branch pushes or manual dispatch.
8. Log source SHA, resolved .config, compiler, kernel release, and checksums.
9. Every kernel update is a deliberate source-lock change. Tests must fail
   on missing mandatory hardware symbols, not silently default.
10. Explicitly distinguish source/config validation, package creation,
    DKMS compatibility, and on-device qualification in status reports.
