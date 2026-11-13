#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
FAILURES=0

pass() {
	printf 'PASS: %s\n' "$1"
}

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	FAILURES=$((FAILURES + 1))
}

test_update_workflow_lease() {
	local workflow
	for workflow in \
		"$REPO_ROOT/.github/workflows/update-proxy-locks.yml" \
		"$REPO_ROOT/.github/workflows/update-init-build-sha.yml"
	do
		if python3 - "$workflow" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    'REMOTE_REF="refs/heads/$BRANCH"',
    'EXPECTED="$(git ls-remote origin "$REMOTE_REF" | awk \'{print $1}\')"',
    'git push --force-with-lease="$REMOTE_REF:$EXPECTED" origin "HEAD:$REMOTE_REF"',
    "concurrency:\n  group:",
    "  cancel-in-progress: false",
]
for fragment in required:
    assert fragment in text, f"missing workflow safeguard: {fragment}"
assert 'git push --force-with-lease origin "$BRANCH"' not in text
PY
		then
			pass "$(basename "$workflow") uses an explicit remote lease and concurrency"
		else
			fail "$(basename "$workflow") must use an explicit remote lease and concurrency"
		fi
	done
}

test_proxy_version_alignment() {
	local fixture recipe tag hash
	fixture="$(mktemp -d)" || { fail 'cannot prepare sing-box recipe fixture'; return; }
	mkdir -p "$fixture/package/sing-box"
	recipe="$fixture/package/sing-box/Makefile"
	tag="$(sed -n 's/^SING_BOX_TAG=v//p' "$REPO_ROOT/.github/proxy-locks.env" | tr -d '\r')"
	hash="$(sed -n 's/^SING_BOX_HASH=//p' "$REPO_ROOT/.github/proxy-locks.env" | tr -d '\r')"
	printf 'PKG_UPSTREAM_VERSION:=%s\nPKG_HASH:=%s\n' "$tag" "$hash" > "$recipe"
	if GITHUB_WORKSPACE="$REPO_ROOT" bash "$SCRIPT_DIR/ApplyProxyLocks.sh" "$fixture"; then
		pass 'the configured sing-box tag, APK version and hash match its package recipe'
	else
		fail 'sing-box package recipe matching the lock must be accepted'
	fi
	printf 'PKG_UPSTREAM_VERSION:=%s\nPKG_HASH:=wrong\n' "$tag" > "$recipe"
	if GITHUB_WORKSPACE="$REPO_ROOT" bash "$SCRIPT_DIR/ApplyProxyLocks.sh" "$fixture" >/dev/null 2>&1; then
		fail 'sing-box recipe with a mismatched source hash must be rejected'
	else
		pass 'sing-box recipe with a mismatched source hash is rejected'
	fi
	rm -rf "$fixture"
}

test_nightly_pr_fallback() {
	local workflow
	for workflow in \
		"$REPO_ROOT/.github/workflows/update-proxy-locks.yml" \
		"$REPO_ROOT/.github/workflows/update-init-build-sha.yml"
	do
		if python3 - "$workflow" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "elif gh pr create",
    "cannot open pull requests in this repository",
    "/compare/${{ github.ref_name }}...$BRANCH?expand=1",
]
forbidden = ['git push origin "HEAD:${{ github.ref_name }}"']
for fragment in required:
    assert fragment in text, f"missing PR fallback: {fragment}"
for fragment in forbidden:
    assert fragment not in text, f"unsafe fallback present: {fragment}"
PY
		then
			pass "$(basename "$workflow") keeps the refreshed locks on its branch when PR creation is blocked"
		else
			fail "$(basename "$workflow") must degrade gracefully when Actions cannot open PRs, without touching the default branch"
		fi
	done
}

test_update_workflow_lease
test_nightly_pr_fallback
test_proxy_version_alignment

if [ "$FAILURES" -eq 0 ]; then
	printf 'OK: recent build regression tests passed\n'
else
	printf 'ERROR: %s regression test(s) failed\n' "$FAILURES" >&2
fi

exit "$FAILURES"
