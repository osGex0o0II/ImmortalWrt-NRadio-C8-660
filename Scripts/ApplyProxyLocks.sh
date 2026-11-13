#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
set -euo pipefail

WRT_DIR="${1:-./wrt}"
REPO_DIR="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
LOCK_FILE="$REPO_DIR/.github/proxy-locks.env"
RECIPE="$WRT_DIR/package/sing-box/Makefile"

if [ ! -s "$LOCK_FILE" ] || [ ! -s "$RECIPE" ]; then
	echo "ERROR: proxy lock or VIKINGYFY sing-box recipe is missing" >&2
	exit 1
fi

read_value() {
	sed -n "s/^$2=//p" "$1" | tr -d '\r'
}

tag="$(read_value "$LOCK_FILE" SING_BOX_TAG)"
version="$(read_value "$LOCK_FILE" SING_BOX_VERSION)"
hash="$(read_value "$LOCK_FILE" SING_BOX_HASH)"
recipe_version="$(sed -n 's/^PKG_UPSTREAM_VERSION:=//p' "$RECIPE" | tr -d '\r')"
recipe_hash="$(sed -n 's/^PKG_HASH:=//p' "$RECIPE" | tr -d '\r')"

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ||
      ! "$hash" =~ ^[0-9a-f]{64}$ ||
      "$tag" != "v$recipe_version" || "$hash" != "$recipe_hash" ]]; then
	echo "ERROR: sing-box recipe does not match the pinned source tag and SHA-256" >&2
	exit 1
fi
expected_version="$(printf '%s' "$recipe_version" | sed -E 's/-(alpha|beta|rc)\./_\1/')"
if [ "$version" != "$expected_version" ]; then
	echo "ERROR: sing-box APK version does not match the pinned source tag" >&2
	exit 1
fi

echo "Verified sing-box recipe: $tag ($version)"
