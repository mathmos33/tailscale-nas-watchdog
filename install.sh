#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/TailscaleNAS"
BIN_DIR="$APP_SUPPORT/bin"
LOG_DIR="$HOME/Library/Logs/TailscaleNAS"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

echo "==> Preparing directories (user space only, no sudo)"
mkdir -p "$BIN_DIR" "$LOG_DIR" "$LAUNCH_AGENTS"

if ! command -v brew &>/dev/null; then
    echo "==> Homebrew not found, installing (may prompt for your password)"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

if ! command -v jq &>/dev/null; then
    echo "==> jq not found, installing via Homebrew"
    brew install jq
fi

echo "==> Installing watchdog.sh"
cp "$DIR/watchdog.sh" "$BIN_DIR/watchdog.sh"
chmod +x "$BIN_DIR/watchdog.sh"

if [ ! -f "$APP_SUPPORT/hosts.json" ]; then
    echo "==> Seeding hosts.json with default servers (edit later via Préférences)"
    cp "$DIR/default-hosts.json" "$APP_SUPPORT/hosts.json"
else
    echo "==> hosts.json already exists, leaving it untouched"
fi

echo "==> Retiring old LaunchAgents (fr.arnaud.*), if present"
for old in fr.arnaud.mount-tm-nas fr.arnaud.tailscale-nas-watchdog fr.arnaud.tailscale-nas-menubar; do
    launchctl unload "$LAUNCH_AGENTS/$old.plist" 2>/dev/null || true
    rm -f "$LAUNCH_AGENTS/$old.plist"
done

echo "==> Installing watchdog LaunchAgent"
sed "s#__HOME__#$HOME#g" "$DIR/com.tailscale-nas-watchdog.watchdog.plist" >"$LAUNCH_AGENTS/com.tailscale-nas-watchdog.watchdog.plist"
launchctl unload "$LAUNCH_AGENTS/com.tailscale-nas-watchdog.watchdog.plist" 2>/dev/null || true
launchctl load "$LAUNCH_AGENTS/com.tailscale-nas-watchdog.watchdog.plist"

echo "==> Building menu bar app"
bash "$DIR/build.sh"

echo "==> Stopping any manually-running instance of the menu bar app"
pkill -f "TailscaleNAS.app/Contents/MacOS/TailscaleNAS" 2>/dev/null || true

echo "==> Installing menu bar app LaunchAgent"
sed "s#__HOME__#$HOME#g" "$DIR/com.tailscale-nas-watchdog.menubar.plist" >"$LAUNCH_AGENTS/com.tailscale-nas-watchdog.menubar.plist"
launchctl unload "$LAUNCH_AGENTS/com.tailscale-nas-watchdog.menubar.plist" 2>/dev/null || true
launchctl load "$LAUNCH_AGENTS/com.tailscale-nas-watchdog.menubar.plist"

echo "==> Done. Status:"
launchctl list | grep -i tailscale-nas-watchdog || echo "(nothing found — something went wrong)"
echo
echo "Logs:      $LOG_DIR/watchdog.log"
echo "State:     $APP_SUPPORT/state.json"
echo "Config:    $APP_SUPPORT/hosts.json  (edit via the menu bar app's Préférences instead)"
