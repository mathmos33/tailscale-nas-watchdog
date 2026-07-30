# Tailscale NAS watchdog — Installation

## Prérequis réels

- **macOS 11 (Big Sur) ou plus récent** — pas de limite haute, ça tourne sur n'importe quelle version au-dessus (testé sur macOS 27.0 bêta). `build.sh` compile avec `-target arm64-apple-macosx11.0`, donc large marge volontaire.
- **Apple Silicon (arm64)** — le binaire n'est PAS universel (pas de code pour Intel/x86_64). Sur un Mac Intel il faudrait ajouter `-target x86_64-apple-macosx11.0` et fusionner avec `lipo`, non fait ici car inutile pour cette machine.
- **`jq`** installé (`brew install jq`, déjà présent ici via Homebrew) — `watchdog.sh` en dépend pour lire/écrire les JSON ; sans lui le script s'arrête proprement avec une erreur explicite dans le journal.
- **Tailscale.app** installé dans `/Applications/` (ou `tailscale` sur le `PATH`).
- **Identifiants SMB déjà enregistrés dans le Trousseau** (`user.ts@...`) — c'est le cas ici suite aux montages manuels précédents ; sur une machine neuve il faudrait monter une première fois à la main pour que macOS propose de sauvegarder le mot de passe.

Montage automatique et auto-réparé des partages SMB sur `nas1`/`nas2` via Tailscale, avec une icône dans la barre de menu pour vérifier/forcer le montage avant une sauvegarde Time Machine.

Contrairement à l'ancienne version (`~/Downloads/tailscale/mount tailscale/`), **tout est installé en espace utilisateur, sans `sudo`**, et les serveurs/identifiants ne sont plus écrits en dur — ils s'éditent depuis l'app.

## Fichiers

| Fichier | Destination |
|---|---|
| `watchdog.sh` | `~/Library/Application Support/TailscaleNAS/bin/watchdog.sh` |
| `default-hosts.json` | copié vers `~/Library/Application Support/TailscaleNAS/hosts.json` **seulement s'il n'existe pas déjà** (ne casse jamais tes modifs) |
| `fr.arnaud.tailscale-nas-watchdog.plist` | `~/Library/LaunchAgents/` |
| `TailscaleNASApp.swift` + `Info.plist` + `AppIcon.icns` | compilés/assemblés par `build.sh` vers `~/Applications/TailscaleNAS.app` |
| `fr.arnaud.tailscale-nas-menubar.plist` | `~/Library/LaunchAgents/` |

`IconGen.swift` + `AppIcon.iconset/` sont les sources de l'icône (même symbole que la barre de menu, blanc sur gris) — `AppIcon.icns` est déjà généré et versionné dans ce dossier, pas besoin de relancer `IconGen.swift` sauf si tu veux changer l'icône.

## Installation

```bash
cd "~/Downloads/tailscale/tailscale-nas-watchdog"
bash install.sh
```

Ça installe tout, désactive l'ancien LaunchAgent (`fr.arnaud.mount-tm-nas`), compile l'app, et charge les deux nouveaux LaunchAgents. Aucun mot de passe admin nécessaire.

## Utilisation au quotidien

- L'icône dans la barre de menu (disque externe = tout va bien, triangle = un souci, réseau barré = Tailscale down) tourne en permanence.
- **Avant une sauvegarde Time Machine réseau** : clique sur l'icône → **"Vérifier maintenant"** pour forcer un check + montage immédiat.
- En tâche de fond, le watchdog revérifie tout **toutes les 60 secondes**, y compris pendant une sauvegarde de plusieurs heures — s'il détecte un partage monté mais dont le serveur n'est plus joignable (montage fantôme), il le démonte proprement puis le remonte dès que le serveur est de nouveau là.
- **Pendant une sauvegarde Time Machine** (détectée via `tmutil status`), le watchdog lance automatiquement `caffeinate -s -i` pour empêcher le Mac de s'endormir (la mise en veille complète coupe Tailscale/SMB — c'est un des suspects probables des coupures aléatoires). Il l'arrête proprement dès que la sauvegarde se termine. Un indicateur "🛡️ Sauvegarde Time Machine en cours — veille bloquée" apparaît dans le menu pendant ce temps.

## Ajouter / renommer / supprimer un serveur

Tout se passe dans **Préférences…** (menu de l'icône) : une table avec Nom / Hôte Tailscale / Chemin / Utilisateur, boutons **+** / **−** pour ajouter/retirer une ligne, **Enregistrer** pour appliquer. Pas besoin d'éditer un fichier à la main, ni de relancer quoi que ce soit — le prochain check (immédiat après "Enregistrer", ou au plus tard dans les 60s) prend en compte le changement.

Le champ **Chemin** est la partie de l'URL SMB après `utilisateur@hôte/` — pour ces NAS Samba, c'est du style `homes/<utilisateur>/<partage>`.

## Relancer l'app après un "Quitter"

Cliquer "Quitter" dans le menu ferme vraiment l'app (ça n'affecte ni les montages ni le watchdog, qui tournent indépendamment). Pour la relancer :

- Double-clic sur `~/Applications/TailscaleNAS.app` dans le Finder, ou
- `launchctl kickstart -k gui/$(id -u)/fr.arnaud.tailscale-nas-menubar` — méthode la plus fiable, contourne Finder/Launch Services.
- Sinon, au prochain login/redémarrage, `RunAtLoad` la relance automatiquement.

## Notes de build (si tu recompiles après une mise à jour de macOS)

`build.sh` compile avec `-target arm64-apple-macosx11.0` et signe le bundle en ad-hoc (`codesign --force --deep --sign -`). Le `-target` explicite est nécessaire : sans lui, `swiftc` embarque par défaut la version du SDK installé (28.0 sur cette machine, plus récente que l'OS réellement installé en 27.0), ce qui fait planter le lancement via Finder avec *"Impossible d'utiliser cette version de l'application avec cette version de macOS"* — le lancement direct (`launchctl`) contournait ce contrôle, mais pas Finder. Fixer `-target` à 11.0 élimine le problème avec une large marge, pas besoin d'ajuster à chaque mise à jour de macOS.

Sans signature ad-hoc, Finder refuse carrément de lancer l'app (icône barrée d'un signe interdit), même sans flag de quarantine — Gatekeeper sur cette bêta semble plus strict que d'habitude pour les apps locales non signées.

## Vérifications

```bash
# Les deux LaunchAgents sont chargés ?
launchctl list | grep arnaud

# Journal en direct (persiste entre reboots, contrairement à /tmp)
tail -f ~/Library/Logs/TailscaleNAS/watchdog.log

# État courant (lu par l'app)
cat ~/Library/Application\ Support/TailscaleNAS/state.json | jq .

# Volumes montés ?
mount | grep smbfs
```

## Diagnostiquer une coupure SMB

La cause des coupures n'est pas encore connue. Le journal enregistre à chaque cycle (60s) : l'état du backend Tailscale, la joignabilité du port 445, et l'état du montage. Quand un montage devient fantôme (serveur injoignable alors que le partage était monté), c'est loggé explicitement :

```
2026-07-27T22:09:13+02:00 host=nas1 backend=Running reachable=no mounted=yes action=STALE_MOUNT_CLEARED result=ok
```

Si ça se reproduit, la prochaine fois :

```bash
# Relever l'heure exacte de la coupure dans le journal
grep STALE_MOUNT_CLEARED ~/Library/Logs/TailscaleNAS/watchdog.log

# Corréler avec les mises en veille/réveil du Mac autour de cette heure-là
pmset -g log | grep -Ei "sleep|wake" | grep "2026-07-27 22:0"

# Corréler avec les logs Tailscale lui-même
tailscale bugreport 2>&1 | head -50
```

Si `⚠︎ Ré-authentification Tailscale requise` apparaît dans le menu, c'est que la clé du nœud a expiré — il faut relancer `tailscale up` manuellement (ouvre le navigateur pour ré-authentifier), le watchdog ne le fera pas tout seul pour éviter de spammer des tentatives inutiles.

## Désinstallation

```bash
launchctl unload ~/Library/LaunchAgents/fr.arnaud.tailscale-nas-watchdog.plist
launchctl unload ~/Library/LaunchAgents/fr.arnaud.tailscale-nas-menubar.plist
rm ~/Library/LaunchAgents/fr.arnaud.tailscale-nas-watchdog.plist
rm ~/Library/LaunchAgents/fr.arnaud.tailscale-nas-menubar.plist
rm -rf ~/Applications/TailscaleNAS.app
rm -rf ~/Library/Application\ Support/TailscaleNAS
rm -rf ~/Library/Logs/TailscaleNAS
```

## Comportement

- Toutes les **60 secondes**, le watchdog vérifie Tailscale + chaque serveur listé dans `hosts.json`.
- Si Tailscale n'est pas `Running` et qu'aucune ré-authentification n'est requise → tentative de reconnexion (`tailscale up`).
- Si un serveur est joignable mais pas monté → montage.
- Si un partage est monté mais que le serveur n'est plus joignable → démontage forcé (montage fantôme nettoyé), puis remontage dès que possible.
- Log dans `~/Library/Logs/TailscaleNAS/watchdog.log` (rotation automatique au-delà de ~5 Mo).
- Si une sauvegarde Time Machine est en cours (`tmutil status`), un `caffeinate -s -i` est maintenu actif pour bloquer la veille système ; son PID est suivi dans `~/Library/Application Support/TailscaleNAS/.caffeinate.pid` et il est arrêté dès que la sauvegarde se termine.
- L'app ne peut tourner qu'en une seule instance à la fois (elle se ferme toute seule si une autre copie est déjà lancée — évite les doublons d'icône si tu double-cliques dessus alors que le LaunchAgent la fait déjà tourner).
