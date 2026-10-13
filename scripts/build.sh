#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Monitor Volume currently supports Apple Silicon Macs only." >&2
    exit 1
fi

swift build -c release --product MonitorVolume --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
DESTINATION="$PWD/dist/MonitorVolume.app"
mkdir -p "$PWD/dist"
STAGING_ROOT="$(mktemp -d "$PWD/dist/.build.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP="$STAGING_ROOT/MonitorVolume.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MonitorVolume" "$APP/Contents/MacOS/MonitorVolume"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp Vendor/AppleSiliconDDC-LICENSE "$APP/Contents/Resources/AppleSiliconDDC-LICENSE.txt"
chmod +x "$APP/Contents/MacOS/MonitorVolume"

# Ad-hoc signing is sufficient for a local build. Set SIGNING_IDENTITY for releases.
codesign --force --sign "${SIGNING_IDENTITY:--}" --options runtime "$APP"
codesign --verify --deep --strict "$APP"
# Replace the bundle rather than overwriting an executable that may still be running.
if [[ -e "$DESTINATION" ]]; then mv "$DESTINATION" "$STAGING_ROOT/previous.app"; fi
if ! mv "$APP" "$DESTINATION"; then
    if [[ -e "$STAGING_ROOT/previous.app" ]]; then mv "$STAGING_ROOT/previous.app" "$DESTINATION"; fi
    exit 1
fi
echo "Built: $DESTINATION"
echo "Quit and reopen the app to use this build."
