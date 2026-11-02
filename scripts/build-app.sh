#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/EnTrans.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EnTrans" "$APP/Contents/MacOS/EnTrans"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/EnTrans"
# A stable identity keeps Screen Recording permission across rebuilds.
# Ad-hoc signatures change every build, so macOS treats each one as a new app.
SIGN_ID="EnTrans Local"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
  codesign --force --timestamp=none --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
