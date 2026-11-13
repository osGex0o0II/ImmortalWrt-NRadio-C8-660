#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
set -euo pipefail

REPO_DIR="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
LOCK_FILE="$REPO_DIR/.github/proxy-locks.env"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Refresh the pair from one commit: its recipe carries the APK version mapping,
# build flags and files required by this HomeProxy revision.
git -c http.proxy= -c https.proxy= clone --quiet --depth=1 --branch main \
	https://github.com/VIKINGYFY/packages.git "$TMP_DIR/packages"
LATEST_HOMEPROXY_COMMIT="$(git -C "$TMP_DIR/packages" rev-parse HEAD)"
RECIPE="$TMP_DIR/packages/sing-box/Makefile"
HOMEPROXY_RECIPE="$TMP_DIR/packages/luci-app-homeproxy/Makefile"
[ -s "$RECIPE" ] && [ -s "$HOMEPROXY_RECIPE" ] || {
	echo "ERROR: VIKINGYFY proxy package recipes are missing" >&2
	exit 1
}

upstream_version="$(sed -n 's/^PKG_UPSTREAM_VERSION:=//p' "$RECIPE" | tr -d '\r')"
expected_hash="$(sed -n 's/^PKG_HASH:=//p' "$RECIPE" | tr -d '\r')"
if [[ ! "$upstream_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ||
      ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]]; then
	echo "ERROR: unexpected sing-box version or SHA-256 in VIKINGYFY recipe" >&2
	exit 1
fi

tag="v$upstream_version"
version="$(printf '%s' "$upstream_version" | sed -E 's/-(alpha|beta|rc)\./_\1/')"
curl -fsSL --retry 5 --retry-all-errors --http1.1 \
	"https://codeload.github.com/SagerNet/sing-box/tar.gz/$tag" -o "$TMP_DIR/sing-box.tar.gz"
hash="$(sha256sum "$TMP_DIR/sing-box.tar.gz" | awk '{print $1}')"
if [ "$hash" != "$expected_hash" ]; then
	echo "ERROR: downloaded sing-box archive does not match the VIKINGYFY SHA-256" >&2
	exit 1
fi

cat > "$LOCK_FILE" <<EOF
SING_BOX_TAG=$tag
SING_BOX_VERSION=$version
SING_BOX_HASH=$hash
PKG_LOCK_homeproxy_BRANCH=main
PKG_LOCK_homeproxy_COMMIT=$LATEST_HOMEPROXY_COMMIT
EOF

echo "Refreshed paired VIKINGYFY locks: sing-box $tag; packages $LATEST_HOMEPROXY_COMMIT"
