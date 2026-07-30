#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/Applications/TailscaleNAS.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if ! command -v swiftc &>/dev/null; then
    echo "==> ERROR: swiftc not found. Install the Xcode Command Line Tools:"
    echo "    xcode-select --install"
    exit 1
fi

case "$(uname -m)" in
    arm64)  SWIFT_TARGET="arm64-apple-macosx11.0" ;;
    x86_64) SWIFT_TARGET="x86_64-apple-macosx11.0" ;;
    *)      echo "==> ERROR: unsupported architecture $(uname -m)"; exit 1 ;;
esac

echo "Compiling TailscaleNASApp.swift..."
swiftc -O -target "$SWIFT_TARGET" "$DIR/TailscaleNASApp.swift" -o "$APP/Contents/MacOS/TailscaleNAS"

cp "$DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/TailscaleNAS"

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"

echo "Built $APP"
