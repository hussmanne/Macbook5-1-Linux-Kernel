#!/usr/bin/env bash
# Tests for install/apply-runtime.sh against throwaway roots.
#
# The deployer is best-effort by design, so the tests assert the *shape* of that
# behaviour: files land in the right places with the right modes, re-running is
# safe, a missing optional package warns without failing, and --verify catches
# both a missing file and a file that drifted from the repository.
set -euo pipefail
cd "$(dirname "$0")/.."
deployer=$PWD/install/apply-runtime.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0 fail=0
ok()  { printf '  ok  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n' "$1" >&2; fail=$((fail+1)); }

new_root() {
  local r=$1
  mkdir -p "$r/etc" "$r/usr/bin" "$r/usr/lib/systemd/system-generators"
  touch "$r/usr/lib/systemd/system-generators/zram-generator"
  printf '%s' "$r"
}

echo "== apply-runtime.sh =="

# 1. Deploy into an empty root: every file, correct mode.
r=$(new_root "$work/a")
out=$(bash "$deployer" --root "$r" 2>&1) || { bad "deploy exited non-zero"; printf '%s\n' "$out" | sed 's/^/       /' >&2; }
for rel in etc/systemd/zram-generator.conf \
           etc/sysctl.d/99-mbp51-memory.conf \
           etc/systemd/system/mbp51-powertop.service \
           usr/lib/systemd/system-sleep/50-mbp51-powertop; do
  [[ -f "$r/$rel" ]] && ok "deployed $rel" || bad "missing $rel"
done
[[ -x "$r/usr/lib/systemd/system-sleep/50-mbp51-powertop" ]] &&
  ok "system-sleep hook is executable" || bad "system-sleep hook not executable"
[[ ! -x "$r/etc/sysctl.d/99-mbp51-memory.conf" ]] &&
  ok "sysctl file is not executable" || bad "sysctl file wrongly executable"

# 2. The deployed bytes are the repo's bytes.
cmp -s "$PWD/runtime/systemd/zram-generator.conf" "$r/etc/systemd/zram-generator.conf" &&
  ok "content matches the repository" || bad "content differs from the repository"

# 3. Idempotent.
bash "$deployer" --root "$r" >/dev/null 2>&1
cmp -s "$PWD/runtime/systemd/zram-generator.conf" "$r/etc/systemd/zram-generator.conf" &&
  ok "re-running is idempotent" || bad "re-run changed the file"

# 4. --verify passes on a good deployment.
bash "$deployer" --root "$r" --verify >"$work/v1" 2>&1 &&
  ok "--verify passes on a clean deployment" || bad "--verify failed on a clean deployment"

# 5. --verify catches a missing file.
rm -f "$r/etc/sysctl.d/99-mbp51-memory.conf"
if bash "$deployer" --root "$r" --verify >"$work/v2" 2>&1; then
  bad "--verify did not fail on a missing file"
else
  grep -q 'MISSING etc/sysctl.d/99-mbp51-memory.conf' "$work/v2" &&
    ok "--verify names the missing file" || bad "--verify failed without naming the file"
fi

# 6. --verify catches drift.
bash "$deployer" --root "$r" >/dev/null 2>&1
printf '\n# tampered\n' >> "$r/etc/systemd/zram-generator.conf"
if bash "$deployer" --root "$r" --verify >"$work/v3" 2>&1; then
  bad "--verify did not fail on a drifted file"
else
  grep -q 'DIFFERS etc/systemd/zram-generator.conf' "$work/v3" &&
    ok "--verify names the drifted file" || bad "--verify failed without naming it"
fi

# 7. Missing zram-generator warns but does not fail (best-effort by design).
r=$(new_root "$work/b")
rm -rf "$r/usr/lib/systemd/system-generators" "$r/usr/bin"
out=$(bash "$deployer" --root "$r" 2>&1)
rc=$?
[[ $rc -eq 0 ]] && ok "missing zram-generator does not fail the deploy" ||
  bad "missing zram-generator exited $rc; best-effort must not fail"
grep -qi 'no swap' <<<"$out" &&
  ok "missing zram-generator warns that there will be no swap" || bad "warning not specific"

# 8. powertop is deferred unless asked for.
[[ ! -e "$r/etc/systemd/system/multi-user.target.wants/mbp51-powertop.service" ]] &&
  ok "powertop unit not enabled by default" || bad "powertop unit enabled by default"

# 9. Bad root is refused.
mkdir -p "$work/notaroot"
if bash "$deployer" --root "$work/notaroot" >/dev/null 2>&1; then
  bad "accepted a directory that is not an install root"
else
  ok "refuses a directory that is not an install root"
fi

# 10. Argument handling.
if bash "$deployer" --bogus >/dev/null 2>&1; then bad "accepted an unknown option"; else ok "rejects an unknown option"; fi
bash "$deployer" --help >/dev/null 2>&1 && ok "--help exits 0" || bad "--help failed"

echo
if (( fail > 0 )); then
  printf 'apply-runtime tests FAILED: %s passed, %s failed\n' "$pass" "$fail" >&2
  exit 1
fi
printf 'apply-runtime tests passed (%s checks).\n' "$pass"
