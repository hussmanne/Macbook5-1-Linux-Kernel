# Repository instructions for coding agents

**Read [LOCAL-MODEL-HANDOFF.md](LOCAL-MODEL-HANDOFF.md) first.** It contains
the physical MacBookPro5,1 findings, the owner's priorities, current builds,
three-tier architecture, specific known failures, reproducible test plan,
repository pointers, and security/boot safety boundaries.

Key rules:
- Never reformat disks or change the current GRUB default automatically.
- Preserve linux-lts and both NVIDIA GPUs, Apple thermals, audio, Wi-Fi and
  kernel/userspace security features other than the explicitly opted-out
  speculative CPU mitigations.
- Keep legacy/Daily/BORE/Lab packages and matching Broadcom modules isolated.
- BORE/Extreme do not exist until real patches and tests prove them.
- Prefer measurable, reversible changes and disclose CI vs physical evidence.
- Start with an inspection of \`git status\`, current CI, and source.lock;
  work in small reviewed branches without clobbering local user edits.
