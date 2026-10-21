#!/usr/bin/env bash
# Fetch the GodotSteam GDExtension into addons/.
#
# The addon is ~100 MB of native libraries and is deliberately git-ignored
# (see .gitignore), so a fresh checkout needs to run this script once before
# online play (and the Steam diagnostics screen) can work:
#
#     tools/fetch_godotsteam.sh            # install if missing
#     tools/fetch_godotsteam.sh --force    # reinstall over an existing copy
#     godot --headless --path . --import   # let Godot import the extension
#
# The release is pinned: version, URL and SHA-256 are recorded below, so the
# same bits are installed everywhere and a corrupted download is rejected.
# Upstream: https://codeberg.org/godotsteam/godotsteam/releases
#
# Exit code: 0 when addons/godotsteam is present (installed now or already
# there), non-zero on download/verification failure.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOTSTEAM_VERSION="4.23.1"
GODOTSTEAM_URL="https://codeberg.org/godotsteam/godotsteam/releases/download/v${GODOTSTEAM_VERSION}/godotsteam-${GODOTSTEAM_VERSION}-gdextension-plugin-4.4.zip.tar.xz"
GODOTSTEAM_SHA256="37d53ede5eda11d2247d70c1af91f95a4777ad2a419fc8a24de1cc816d21cc0a"

TARGET="$ROOT/addons/godotsteam"
FORCE=0
if [ "${1:-}" = "--force" ]; then
	FORCE=1
fi

if [ -e "$TARGET/godotsteam.gdextension" ] && [ "$FORCE" -ne 1 ]; then
	echo "PASS  addons/godotsteam already present (version $GODOTSTEAM_VERSION); use --force to reinstall"
	exit 0
fi

TMPDIR_FETCH="$(mktemp -d "${TMPDIR:-/tmp}/gh-godotsteam.XXXXXX")"
cleanup() { rm -rf "$TMPDIR_FETCH"; }
trap cleanup EXIT

ARCHIVE="$TMPDIR_FETCH/godotsteam.zip.tar.xz"

echo "════════════════════════════════════════════════════════════"
echo " fetch GodotSteam $GODOTSTEAM_VERSION  ·  ~18 MiB download"
echo "════════════════════════════════════════════════════════════"

if command -v curl >/dev/null 2>&1; then
	curl -fL --retry 3 -o "$ARCHIVE" "$GODOTSTEAM_URL" || { echo "FAIL  download failed"; exit 1; }
elif command -v wget >/dev/null 2>&1; then
	wget -O "$ARCHIVE" "$GODOTSTEAM_URL" || { echo "FAIL  download failed"; exit 1; }
else
	echo "FAIL  neither curl nor wget is available"
	exit 1
fi

ACTUAL_SHA256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$GODOTSTEAM_SHA256" ]; then
	echo "FAIL  checksum mismatch"
	echo "      expected $GODOTSTEAM_SHA256"
	echo "      actual   $ACTUAL_SHA256"
	exit 1
fi
echo "checksum ok"

if [ "$FORCE" -eq 1 ]; then
	rm -rf "$TARGET"
fi
tar -xJf "$ARCHIVE" -C "$ROOT" || { echo "FAIL  extraction failed"; exit 1; }

if [ ! -e "$TARGET/godotsteam.gdextension" ]; then
	echo "FAIL  archive did not produce addons/godotsteam/godotsteam.gdextension"
	exit 1
fi

echo "PASS  addons/godotsteam installed ($GODOTSTEAM_VERSION)"
echo "next: godot --headless --path . --import"
