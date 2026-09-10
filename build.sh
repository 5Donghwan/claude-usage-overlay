#!/bin/bash
# Build the overlay and package it as a minimal .app bundle (stable TCC identity).
set -euo pipefail
cd "$(dirname "$0")"

CERT_NAME="ClaudeUsageOverlay Local Signing"

./scripts/ensure-signing-identity.sh

swift build -c release

APP=dist/ClaudeUsageOverlay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/ClaudeUsageOverlay "$APP/Contents/MacOS/"
codesign --force -s "$CERT_NAME" "$APP"
echo "built: $APP"

# Signed with a stable local identity (not ad-hoc), so the Accessibility grant
# survives rebuilds. Only the very first run after switching to this identity
# needs a fresh approval — after that, TCC recognizes the same signer.
