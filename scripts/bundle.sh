#!/bin/zsh
# Builds "Monitor Minder.app" from the Swift package.
#   scripts/bundle.sh [debug|release]
# Environment:
#   VERSION        version string for Info.plist (default 0.1.0)
#   SIGN_IDENTITY  codesigning identity. Defaults to a local Apple Development identity, then
#                  ad-hoc. A stable identity keeps the Accessibility approval across rebuilds.
set -euo pipefail
cd "${0:A:h}/.."
CONFIG=${1:-release}
VERSION=${VERSION:-0.1.0}

swift build -c "$CONFIG" --product MonitorMinder
BIN=$(swift build -c "$CONFIG" --show-bin-path)

APP="build/Monitor Minder.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MonitorMinder" "$APP/Contents/MacOS/MonitorMinder"
sed "s/__VERSION__/$VERSION/" Resources/Info.plist > "$APP/Contents/Info.plist"

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}
codesign --force --sign "${IDENTITY:--}" --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc}"
echo "Built $APP ($VERSION)"
