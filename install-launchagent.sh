#!/bin/bash
# Generates a LaunchAgent plist bound to THIS checkout's actual path and loads it,
# so the overlay starts automatically at login. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")"
REPO_DIR="$(pwd)"
EXEC="$REPO_DIR/dist/ClaudeUsageOverlay.app/Contents/MacOS/ClaudeUsageOverlay"
LABEL="local.claude-usage-overlay"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -x "$EXEC" ]; then
  echo "error: not built yet — run ./build.sh first" >&2
  exit 1
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$EXEC</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "installed and loaded: $PLIST"
echo "  -> $EXEC"
echo "to remove: launchctl unload \"$PLIST\" && rm \"$PLIST\""
