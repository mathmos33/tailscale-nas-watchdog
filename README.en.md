# Tailscale NAS watchdog — Installation

*This is a translation of [`README.md`](README.md) (source of truth, French). Keep both in sync when editing.*

## Actual prerequisites

- **macOS 11 (Big Sur) or later** — no upper bound, runs on anything above (tested on macOS 27.0 beta).
- **Apple Silicon (arm64) or Intel (x86_64)** — `build.sh` detects the architecture (`uname -m`) and picks the right `-target` for `swiftc` automatically. The resulting binary is NOT universal (no `lipo`), but compiles natively on both families.
- **Xcode Command Line Tools** (for `swiftc`) — `build.sh` checks for their presence and stops with a clear message (`xcode-select --install`) if missing; this is the only step that stays manual, since the install opens a GUI window that can't be scripted all the way through.
- **Homebrew and `jq`** — `install.sh` installs them automatically if missing (Homebrew via its official script in `NONINTERACTIVE` mode, then `brew install jq`). Nothing to do by hand unless you'd rather install them yourself first.
- **Tailscale.app** installed in `/Applications/` (or `tailscale` on `PATH`) — **not automated**, install it manually before `install.sh`.
- **SMB credentials saved in Keychain** — on a fresh machine, you need to mount each share once by hand (Finder → `Go → Connect to Server…` → `smb://user@host/path`) so macOS offers to save the password. The watchdog doesn't handle initial authentication, only mounting/remounting once credentials are already known to the system.

Automatic, self-healing mounting of SMB shares on `nas1`/`nas2` over Tailscale, with a menu bar icon to check/force the mount before a Time Machine backup.

Unlike the old version (`~/Downloads/tailscale/mount tailscale/`), **everything is installed in user space, no `sudo`**, and servers/credentials are no longer hardcoded — they're edited from the app.

## Files

| File | Destination |
|---|---|
| `watchdog.sh` | `~/Library/Application Support/TailscaleNAS/bin/watchdog.sh` |
| `default-hosts.json` | copied to `~/Library/Application Support/TailscaleNAS/hosts.json` **only if it doesn't already exist** (never clobbers your edits) |
| `com.tailscale-nas-watchdog.watchdog.plist` | `~/Library/LaunchAgents/` (the `__HOME__` placeholder is replaced with your real `$HOME` at install time, so it's portable across machines/accounts) |
| `TailscaleNASApp.swift` + `Info.plist` + `AppIcon.icns` | compiled/assembled by `build.sh` into `~/Applications/TailscaleNAS.app` |
| `com.tailscale-nas-watchdog.menubar.plist` | `~/Library/LaunchAgents/` (same `__HOME__` substitution) |

`IconGen.swift` + `AppIcon.iconset/` are the icon sources (same symbol as the menu bar, white on gray) — `AppIcon.icns` is already generated and checked into this folder, no need to rerun `IconGen.swift` unless you want to change the icon.

## Installation

```bash
cd "~/Downloads/tailscale/tailscale-nas-watchdog"
bash install.sh
```

`install.sh` does, in order:

1. Installs **Homebrew** if missing (may ask for your password to create `/opt/homebrew`), then **`jq`** via `brew install jq` if missing.
2. Copies `watchdog.sh` into user space.
3. Seeds `hosts.json` with `default-hosts.json` if absent (never touches an existing `hosts.json`).
4. Disables old LaunchAgents (`fr.arnaud.mount-tm-nas` and, when upgrading from an earlier version, `fr.arnaud.tailscale-nas-watchdog`/`fr.arnaud.tailscale-nas-menubar`), installs the new one (`com.tailscale-nas-watchdog.watchdog`).
5. Calls `build.sh` (compiles + signs the app — see checks below, fails cleanly if Xcode CLT is missing).
6. Installs and loads the menu bar app's LaunchAgent.

No explicit `sudo` anywhere in the script; the only password prompt, if any, comes from the Homebrew installer itself if it isn't already present.

### On a fresh machine

What's **automated** by `install.sh`/`build.sh`: Homebrew, `jq`, `.plist` templating, architecture detection for compilation, Xcode CLT check.

What stays **manual**, in this order:

1. Install **Tailscale.app** and authenticate (`tailscale up`).
2. Accept the **Xcode Command Line Tools** install prompt if asked (`xcode-select --install`, GUI popup).
3. Mount each SMB share once by hand so macOS saves the password in Keychain (see Prerequisites above).
4. Run `bash install.sh`.

## Day-to-day use

- The menu bar icon (connected external drive = all good, triangle = an issue, crossed-out network = Tailscale down) runs continuously.
- **Before a network Time Machine backup**: click the icon → **"Vérifier maintenant"** (Check now) to force an immediate check + mount.
- In the background, the watchdog rechecks everything **every 60 seconds**, including during a multi-hour backup — if it detects a share that's mounted but whose server is no longer reachable (a stale mount), it unmounts it cleanly and remounts it as soon as the server is back.
- **During a Time Machine backup** (detected via `tmutil status`), the watchdog automatically runs `caffeinate -s -i` to keep the Mac from sleeping (full sleep drops Tailscale/SMB — one of the likely suspects for random disconnects). It stops it cleanly as soon as the backup finishes. A "🛡️ Sauvegarde Time Machine en cours — veille bloquée" (Time Machine backup running — sleep blocked) indicator appears in the menu during that time.

## Adding / renaming / removing a server

Everything happens in **Préférences…** (Preferences, from the icon's menu): a table with Name / Tailscale Host / Path / Username, **+** / **−** buttons to add/remove a row, **Enregistrer** (Save) to apply. No need to hand-edit a file or restart anything — the next check (immediate after "Enregistrer", or within 60s at the latest) picks up the change.

The **Path** field is the part of the SMB URL after `user@host/` — for these Samba NAS boxes, it looks like `homes/<user>/<share>`.

## Relaunching the app after "Quitter"

Clicking "Quitter" (Quit) in the menu really closes the app (it doesn't affect mounts or the watchdog, which run independently). To relaunch it:

- Double-click `~/Applications/TailscaleNAS.app` in Finder, or
- `launchctl kickstart -k gui/$(id -u)/com.tailscale-nas-watchdog.menubar` — most reliable method, bypasses Finder/Launch Services.
- Otherwise, at the next login/reboot, `RunAtLoad` relaunches it automatically.

## Build notes (if you recompile after a macOS update)

`build.sh` compiles with `-target <arch>-apple-macosx11.0` (`<arch>` = `arm64` or `x86_64` depending on `uname -m`). The explicit `-target` is necessary: without it, `swiftc` defaults to embedding the installed SDK version (28.0 on this machine, newer than the OS actually installed, 27.0), which makes launching via Finder fail with *"This version of the app can't be used with this version of macOS"* — launching directly (`launchctl`) bypassed that check, but Finder didn't. Pinning the `-target` macOS version to 11.0 eliminates the problem with a wide margin, no need to bump it on every macOS update.

Without a signature, Finder flatly refuses to launch the app (icon with a "not allowed" badge), even without a quarantine flag — Gatekeeper on this beta seems stricter than usual for unsigned local apps. The app is signed with a **stable self-signed certificate** (`TailscaleNAS Local Signing`), generated once per machine in the login Keychain and reused on every rebuild (`build.sh` detects it via `security find-identity` and only recreates it if missing). An **ad-hoc** signature (`--sign -`) would have been simpler, but it changes hash on every rebuild, which silently invalidates the TCC permissions already granted to the app (Full Disk Access, Network Volumes) — so the `.metadata_never_index` flag (see below) stopped being set after every `install.sh`. With the stable certificate, the *designated requirement* stays tied to the certificate (`certificate leaf = H"…"`) rather than the binary, so permissions survive rebuilds.

If you need to regenerate the certificate from scratch (lost, corrupted, etc.): `security delete-certificate -c "TailscaleNAS Local Signing" ~/Library/Keychains/login.keychain-db`, then rerun `build.sh` — it creates a new one. You'll then need to re-grant the TCC permissions one last time (see next section).

## Checks

```bash
# Are both LaunchAgents loaded?
launchctl list | grep tailscale-nas-watchdog

# Live log (persists across reboots, unlike /tmp)
tail -f ~/Library/Logs/TailscaleNAS/watchdog.log

# Current state (read by the app)
cat ~/Library/Application\ Support/TailscaleNAS/state.json | jq .

# Mounted volumes?
mount | grep smbfs
```

## Diagnosing an SMB dropout

The cause of the dropouts isn't known yet. The log records, on every cycle (60s): Tailscale backend state, port 445 reachability, and mount state. When a mount goes stale (server unreachable while the share was mounted), it's logged explicitly:

```
2026-07-27T22:09:13+02:00 host=nas1 backend=Running reachable=no mounted=yes action=STALE_MOUNT_CLEARED result=ok
```

If it happens again, next time:

```bash
# Get the exact time of the dropout from the log
grep STALE_MOUNT_CLEARED ~/Library/Logs/TailscaleNAS/watchdog.log

# Correlate with the Mac's sleep/wake events around that time
pmset -g log | grep -Ei "sleep|wake" | grep "2026-07-27 22:0"

# Correlate with Tailscale's own logs
tailscale bugreport 2>&1 | head -50
```

If `⚠︎ Ré-authentification Tailscale requise` (Tailscale re-authentication required) shows up in the menu, the node key has expired — you need to run `tailscale up` manually (opens the browser to re-authenticate); the watchdog won't do it on its own, to avoid spamming useless attempts.

## Uninstalling

```bash
bash uninstall.sh
```

Unloads and removes both LaunchAgents (+ the old `fr.arnaud.*` ones if still around), removes the app and the logs. By default, **`hosts.json` is kept** (in case you reinstall later); to wipe everything including your server config:

```bash
bash uninstall.sh --purge
```

Already-mounted volumes and Keychain credentials are left untouched — unmount/remove them yourself if needed.

## Behavior

- Every **60 seconds**, the watchdog checks Tailscale + every server listed in `hosts.json`.
- If Tailscale isn't `Running` and no re-authentication is required → reconnect attempt (`tailscale up`).
- If a server is reachable but not mounted → mount it.
- As long as a volume is mounted (one of the hosts tracked in `hosts.json`, or any other SMB share mounted under `/Volumes` — e.g. "Films" or "homes" reached by browsing the NAS from Finder), a `.metadata_never_index` file is kept at its root to disable Spotlight indexing on it (no `mdutil`/sudo needed — useful since Spotlight has no business on network shares, especially not the one used for Time Machine). **The menu bar app is what sets this flag reliably**, not `watchdog.sh`: a headless `launchd` process can't obtain the macOS "Files and Folders → Network Volumes" permission (macOS has no way to show it the consent popup, so the write is silently denied). `watchdog.sh` still attempts the `touch` on a best-effort basis (it works if you rerun it by hand from Terminal, which already has that permission) but it isn't reliable in the background — **the menu bar app needs to be running** for the flag to be set reliably. Shares not listed in `hosts.json` are also listed in the menu, under "Autres partages montés (non suivis)" (Other mounted shares, untracked) (no auto-remount for those, just display + Spotlight flag).
- Checking this flag is a network `stat` (and potentially a write) over SMB — done in a loop without care, it's enough to saturate the SMB session shared with Finder and cause multi-second system-wide freezes. Both processes that touch this flag therefore cache it as soon as it's confirmed present, so a known-good mount is never re-stated:
  - **Menu bar app**: in-memory cache (`Set<String>` of confirmed mount points), the 5s refresh no longer makes the network call once a mount is confirmed.
  - **`watchdog.sh`**: on-disk cache (`~/Library/Application Support/TailscaleNAS/.spotlight_confirmed`), a confirmed mount point isn't re-stated on later cycles (60s). This cache is cleared on every real Mac reboot (same mechanism as log rotation, based on `sysctl kern.boottime`) so it re-checks cleanly after a reboot or a share change.
- If a share is mounted but the server is no longer reachable → forced unmount (stale mount cleared), then remounted as soon as possible.
- Logs to `~/Library/Logs/TailscaleNAS/watchdog.log`, reset on every real Mac reboot (detected via `sysctl kern.boottime`, compared against `~/Library/Application Support/TailscaleNAS/.last_boot` — so a plain `launchctl kickstart`/reinstall doesn't clear it, only a real reboot does), otherwise auto-rotated past ~5 MB within the same session.
- If a Time Machine backup is running (`tmutil status`), a `caffeinate -s -i` is kept alive to block system sleep; its PID is tracked in `~/Library/Application Support/TailscaleNAS/.caffeinate.pid` and it's stopped as soon as the backup finishes.
- The app can only run as a single instance at a time (it quits itself if another copy is already running — avoids duplicate icons if you double-click it while the LaunchAgent is already running it).
