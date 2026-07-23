#!/bin/bash
# Build the overlay and package it as a minimal .app bundle (stable TCC identity).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=dist/ClaudeUsageOverlay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/ClaudeUsageOverlay "$APP/Contents/MacOS/"
codesign --force -s - "$APP"
echo "built: $APP"

# Ad-hoc re-signing invalidates the Accessibility grant AND leaves a stale TCC
# entry that silently ignores re-toggling. Clear it so the fresh prompt binds
# to the new binary. (Verified behavior, 2026-07-23.)
tccutil reset Accessibility local.claude-usage-overlay >/dev/null 2>&1 || true
echo "note: Accessibility 권한을 다시 승인해야 합니다 (앱 실행 시 프롬프트가 뜸)"
