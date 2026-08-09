#!/bin/bash
#
# Tailscale NAS watchdog.
# Reads hosts.json fresh every run, reconciles Tailscale + SMB mount state,
# and writes state.json for the menu bar app to display.

APP_SUPPORT="$HOME/Library/Application Support/TailscaleNAS"
HOSTS_JSON="$APP_SUPPORT/hosts.json"
STATE_JSON="$APP_SUPPORT/state.json"
LOG_DIR="$HOME/Library/Logs/TailscaleNAS"
LOG_FILE="$LOG_DIR/watchdog.log"
LAST_WARN_FILE="$APP_SUPPORT/.last_auth_warning"
CAFFEINATE_PID_FILE="$APP_SUPPORT/.caffeinate.pid"
LAST_BOOT_FILE="$APP_SUPPORT/.last_boot"
AUTH_WARN_INTERVAL=600
LOG_MAX_BYTES=$((5 * 1024 * 1024))

mkdir -p "$APP_SUPPORT" "$LOG_DIR"

log() {
    echo "$(date -Iseconds) $*" >>"$LOG_FILE"
}

# Looks for a mount source line in $1, trying the primary pattern $2 first and
# falling back to $3 if that doesn't match (used because we can't be 100% sure
# whether mount(8) displays a decoded space or a literal %20 for paths with spaces).
find_mount_line() {
    local table="$1" primary="$2" fallback="$3" line
    line=$(echo "$table" | grep -F -- "$primary ")
    if [ -z "$line" ] && [ "$primary" != "$fallback" ]; then
        line=$(echo "$table" | grep -F -- "$fallback ")
    fi
    echo "$line"
}

# --- reset log on new boot session (RunAtLoad fires on every launchctl
# load/kickstart too, so we compare against the kernel's actual boot time
# rather than assuming "we just ran" means "the Mac just started") ---
current_boot=$(sysctl -n kern.boottime 2>/dev/null | grep -oE '[0-9]+' | head -1)
if [ -n "$current_boot" ] && [ "$(cat "$LAST_BOOT_FILE" 2>/dev/null)" != "$current_boot" ]; then
    : >"$LOG_FILE"
    echo "$current_boot" >"$LAST_BOOT_FILE"
    log "Log reset: new boot session (kern.boottime=$current_boot)"
fi

# --- log rotation ---
if [ -f "$LOG_FILE" ]; then
    size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
        tail -n 3000 "$LOG_FILE" >"$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
fi

# --- Time Machine detection & sleep prevention ---
TM_STATUS=$(tmutil status 2>/dev/null)
TM_RUNNING_RAW=$(echo "$TM_STATUS" | awk -F'= ' '/Running/{gsub(/[^0-9]/,"",$2); print $2}')
if [ "$TM_RUNNING_RAW" = "1" ]; then
    TM_RUNNING=yes
    if [ ! -f "$CAFFEINATE_PID_FILE" ] || ! kill -0 "$(cat "$CAFFEINATE_PID_FILE" 2>/dev/null)" 2>/dev/null; then
        /usr/bin/caffeinate -s -i >/dev/null 2>&1 &
        disown
        echo $! >"$CAFFEINATE_PID_FILE"
        log "Time Machine backup detected — caffeinate started (pid $(cat "$CAFFEINATE_PID_FILE")) to prevent sleep"
    fi
else
    TM_RUNNING=no
    if [ -f "$CAFFEINATE_PID_FILE" ]; then
        pid=$(cat "$CAFFEINATE_PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            log "Time Machine backup finished — caffeinate (pid $pid) stopped"
        fi
        rm -f "$CAFFEINATE_PID_FILE"
    fi
fi

# --- locate tailscale CLI ---
TAILSCALE_BIN=""
for candidate in "/Applications/Tailscale.app/Contents/MacOS/tailscale" "/usr/local/bin/tailscale" "/opt/homebrew/bin/tailscale"; do
    if [ -x "$candidate" ]; then
        TAILSCALE_BIN="$candidate"
        break
    fi
done
if [ -z "$TAILSCALE_BIN" ]; then
    TAILSCALE_BIN=$(command -v tailscale 2>/dev/null)
fi

if ! command -v jq &>/dev/null; then
    log "ERROR jq not found on PATH (install via 'brew install jq')"
    exit 1
fi

if [ -z "$TAILSCALE_BIN" ]; then
    log "ERROR tailscale CLI not found"
    jq -n --arg ts "$(date -Iseconds)" --argjson tm "$([ "$TM_RUNNING" = "yes" ] && echo true || echo false)" \
        '{backendState:"Unknown", authPending:false, lastCheck:$ts, timeMachineRunning:$tm, hosts:[], error:"tailscale CLI not found"}' \
        >"$STATE_JSON"
    exit 1
fi

if [ ! -f "$HOSTS_JSON" ]; then
    log "ERROR hosts.json not found at $HOSTS_JSON"
    jq -n --arg ts "$(date -Iseconds)" --argjson tm "$([ "$TM_RUNNING" = "yes" ] && echo true || echo false)" \
        '{backendState:"Unknown", authPending:false, lastCheck:$ts, timeMachineRunning:$tm, hosts:[], error:"hosts.json not found"}' \
        >"$STATE_JSON"
    exit 1
fi

# --- tailscale backend health ---
TS_JSON=$("$TAILSCALE_BIN" status --json 2>/dev/null)
BACKEND_STATE=$(echo "$TS_JSON" | jq -r '.BackendState // "Unknown"')
AUTH_URL=$(echo "$TS_JSON" | jq -r '.AuthURL // ""')

if [ "$BACKEND_STATE" != "Running" ]; then
    if [ -n "$AUTH_URL" ]; then
        now=$(date +%s)
        last=0
        [ -f "$LAST_WARN_FILE" ] && last=$(cat "$LAST_WARN_FILE" 2>/dev/null || echo 0)
        if [ $((now - last)) -ge $AUTH_WARN_INTERVAL ]; then
            log "WARNING tailscale needs interactive re-authentication: $AUTH_URL"
            echo "$now" >"$LAST_WARN_FILE"
        fi
    else
        log "backend=$BACKEND_STATE attempting reconnect (tailscale up)"
        "$TAILSCALE_BIN" up >>"$LOG_FILE" 2>&1
        sleep 2
        TS_JSON=$("$TAILSCALE_BIN" status --json 2>/dev/null)
        BACKEND_STATE=$(echo "$TS_JSON" | jq -r '.BackendState // "Unknown"')
        log "backend now $BACKEND_STATE after reconnect attempt"
    fi
fi

# --- per-host reconciliation ---
MOUNT_TABLE=$(mount)
HOST_STATES=()

while IFS= read -r host_json; do
    id=$(echo "$host_json" | jq -r '.id')
    name=$(echo "$host_json" | jq -r '.name')
    ts_host=$(echo "$host_json" | jq -r '.tsHost')
    path=$(echo "$host_json" | jq -r '.path')
    username=$(echo "$host_json" | jq -r '.username')

    path_noslash="${path%/}"
    # Normalize so the path works whether entered with a literal space or a
    # pre-encoded %20 (e.g. "Time Machine" vs "Time%20Machine"):
    path_encoded="${path_noslash// /%20}"    # for the URL passed to osascript — always needs %20
    path_decoded="${path_noslash//%20/ }"    # most likely how mount(8) displays it — primary match
    smb_url="smb://${username}@${ts_host}/${path_encoded}"
    src_pattern="//${username}@${ts_host}/${path_decoded}"
    src_pattern_fallback="//${username}@${ts_host}/${path_noslash}"

    if nc -z -G 2 "$ts_host" 445 &>/dev/null; then
        reachable=yes
    else
        reachable=no
    fi

    mount_line=$(find_mount_line "$MOUNT_TABLE" "$src_pattern" "$src_pattern_fallback")
    if [ -n "$mount_line" ]; then
        mounted=yes
        mount_point=$(echo "$mount_line" | sed -E 's#.* on (/Volumes/[^ ]+) \(.*#\1#')
    else
        mounted=no
        mount_point=""
    fi

    action="none"
    result="n/a"

    if [ "$reachable" = "yes" ] && [ "$mounted" = "no" ]; then
        action="mount"
        /usr/bin/osascript -e "mount volume \"$smb_url\"" >/dev/null 2>&1
        MOUNT_TABLE=$(mount)
        mount_line=$(find_mount_line "$MOUNT_TABLE" "$src_pattern" "$src_pattern_fallback")
        if [ -n "$mount_line" ]; then
            mounted=yes
            mount_point=$(echo "$mount_line" | sed -E 's#.* on (/Volumes/[^ ]+) \(.*#\1#')
            result=ok
            # Spotlight indexing a network share wastes CPU/bandwidth and can
            # interfere with Time Machine; this flag is honored without mdutil/sudo.
            touch "$mount_point/.metadata_never_index" 2>/dev/null
        else
            result=failed
        fi
    elif [ "$reachable" = "no" ] && [ "$mounted" = "yes" ]; then
        action="STALE_MOUNT_CLEARED"
        if diskutil unmount force "$mount_point" >/dev/null 2>&1; then
            result=ok
        else
            result=failed
        fi
        mounted=no
        MOUNT_TABLE=$(mount)
        mount_point=""
    fi

    log "host=$name backend=$BACKEND_STATE reachable=$reachable mounted=$mounted action=$action result=$result"

    host_state=$(jq -n \
        --arg id "$id" --arg name "$name" --arg tsHost "$ts_host" \
        --arg path "$path" --arg username "$username" \
        --arg reachable "$reachable" --arg mounted "$mounted" \
        --arg mountPoint "$mount_point" --arg action "$action" --arg result "$result" \
        '{id:$id, name:$name, tsHost:$tsHost, path:$path, username:$username,
          reachable:($reachable=="yes"), mounted:($mounted=="yes"),
          mountPoint:$mountPoint, lastAction:$action, lastResult:$result}')
    HOST_STATES+=("$host_state")
done < <(jq -c '.[]' "$HOSTS_JSON")

hosts_array=$(printf '%s\n' "${HOST_STATES[@]}" | jq -s '.')

jq -n \
    --arg backend "$BACKEND_STATE" --arg authUrl "$AUTH_URL" --arg ts "$(date -Iseconds)" \
    --argjson tm "$([ "$TM_RUNNING" = "yes" ] && echo true || echo false)" \
    --argjson hosts "$hosts_array" \
    '{backendState:$backend, authPending:($authUrl!=""), lastCheck:$ts, timeMachineRunning:$tm, hosts:$hosts}' \
    >"$STATE_JSON.tmp" && mv "$STATE_JSON.tmp" "$STATE_JSON"
