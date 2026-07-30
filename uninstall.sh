#!/bin/bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/TailscaleNAS"
LOG_DIR="$HOME/Library/Logs/TailscaleNAS"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

PURGE=0
if [ "${1:-}" = "--purge" ]; then
    PURGE=1
fi

echo "==> Stopping any running instance of the menu bar app"
pkill -f "TailscaleNAS.app/Contents/MacOS/TailscaleNAS" 2>/dev/null || true

echo "==> Unloading and removing LaunchAgents"
for label in com.tailscale-nas-watchdog.watchdog com.tailscale-nas-watchdog.menubar \
             fr.arnaud.tailscale-nas-watchdog fr.arnaud.tailscale-nas-menubar fr.arnaud.mount-tm-nas; do
    launchctl unload "$LAUNCH_AGENTS/$label.plist" 2>/dev/null || true
    rm -f "$LAUNCH_AGENTS/$label.plist"
done

echo "==> Removing menu bar app"
rm -rf "$HOME/Applications/TailscaleNAS.app"

echo "==> Removing logs"
rm -rf "$LOG_DIR"

if [ "$PURGE" -eq 1 ]; then
    echo "==> --purge: removing config and state ($APP_SUPPORT, includes hosts.json)"
    rm -rf "$APP_SUPPORT"
else
    echo "==> Removing watchdog.sh binary and cached state, keeping hosts.json"
    rm -f "$APP_SUPPORT/bin/watchdog.sh"
    rmdir "$APP_SUPPORT/bin" 2>/dev/null || true
    rm -f "$APP_SUPPORT/state.json" "$APP_SUPPORT/.last_auth_warning" "$APP_SUPPORT/.caffeinate.pid"
    echo "    (hosts.json kept at: $APP_SUPPORT/hosts.json — rerun with --purge to remove it too)"
fi

echo "==> Note: mounted SMB volumes and Keychain entries are left untouched."
echo "==> Done."
