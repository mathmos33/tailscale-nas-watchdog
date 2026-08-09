# Tailscale NAS watchdog — Installation

## Prérequis réels

- **macOS 11 (Big Sur) ou plus récent** — pas de limite haute, ça tourne sur n'importe quelle version au-dessus (testé sur macOS 27.0 bêta).
- **Apple Silicon (arm64) ou Intel (x86_64)** — `build.sh` détecte l'architecture (`uname -m`) et choisit automatiquement le bon `-target` pour `swiftc`. Le binaire produit n'est PAS universel (pas de `lipo`), mais compile nativement sur les deux familles.
- **Xcode Command Line Tools** (pour `swiftc`) — `build.sh` vérifie sa présence et s'arrête avec un message clair (`xcode-select --install`) si absent ; c'est la seule étape qui reste manuelle car l'installation ouvre une fenêtre GUI et ne peut pas être scriptée jusqu'au bout.
- **Homebrew et `jq`** — `install.sh` les installe automatiquement s'ils manquent (Homebrew via son script officiel en mode `NONINTERACTIVE`, puis `brew install jq`). Rien à faire à la main sauf si tu préfères les installer toi-même avant.
- **Tailscale.app** installé dans `/Applications/` (ou `tailscale` sur le `PATH`) — **non automatisé**, à installer manuellement avant `install.sh`.
- **Identifiants SMB enregistrés dans le Trousseau** — sur une machine neuve, il faut monter chaque partage une première fois à la main (Finder → `Aller → Se connecter au serveur…` → `smb://utilisateur@hôte/chemin`) pour que macOS propose de sauvegarder le mot de passe. Le watchdog ne gère pas l'authentification initiale, seulement le montage/remontage une fois les identifiants connus du système.

Montage automatique et auto-réparé des partages SMB sur `nas1`/`nas2` via Tailscale, avec une icône dans la barre de menu pour vérifier/forcer le montage avant une sauvegarde Time Machine.

Contrairement à l'ancienne version (`~/Downloads/tailscale/mount tailscale/`), **tout est installé en espace utilisateur, sans `sudo`**, et les serveurs/identifiants ne sont plus écrits en dur — ils s'éditent depuis l'app.

## Fichiers

| Fichier | Destination |
|---|---|
| `watchdog.sh` | `~/Library/Application Support/TailscaleNAS/bin/watchdog.sh` |
| `default-hosts.json` | copié vers `~/Library/Application Support/TailscaleNAS/hosts.json` **seulement s'il n'existe pas déjà** (ne casse jamais tes modifs) |
| `com.tailscale-nas-watchdog.watchdog.plist` | `~/Library/LaunchAgents/` (le placeholder `__HOME__` est remplacé par ton `$HOME` réel à l'install, donc portable d'une machine/d'un compte à l'autre) |
| `TailscaleNASApp.swift` + `Info.plist` + `AppIcon.icns` | compilés/assemblés par `build.sh` vers `~/Applications/TailscaleNAS.app` |
| `com.tailscale-nas-watchdog.menubar.plist` | `~/Library/LaunchAgents/` (même substitution `__HOME__`) |

`IconGen.swift` + `AppIcon.iconset/` sont les sources de l'icône (même symbole que la barre de menu, blanc sur gris) — `AppIcon.icns` est déjà généré et versionné dans ce dossier, pas besoin de relancer `IconGen.swift` sauf si tu veux changer l'icône.

## Installation

```bash
cd "~/Downloads/tailscale/tailscale-nas-watchdog"
bash install.sh
```

`install.sh` fait, dans l'ordre :

1. Installe **Homebrew** s'il manque (peut demander ton mot de passe pour créer `/opt/homebrew`), puis **`jq`** via `brew install jq` s'il manque.
2. Copie `watchdog.sh` en espace utilisateur.
3. Sème `hosts.json` avec `default-hosts.json` si absent (ne touche jamais un `hosts.json` existant).
4. Désactive les anciens LaunchAgents (`fr.arnaud.mount-tm-nas` et, pour une mise à jour depuis une version antérieure, `fr.arnaud.tailscale-nas-watchdog`/`fr.arnaud.tailscale-nas-menubar`), installe le nouveau (`com.tailscale-nas-watchdog.watchdog`).
5. Appelle `build.sh` (compile + signe ad-hoc l'app — voir vérifications ci-dessous, échoue proprement si Xcode CLT manque).
6. Installe et charge le LaunchAgent de l'app barre de menu.

Aucun `sudo` explicite dans le script ; le seul mot de passe éventuellement demandé vient de l'installateur Homebrew lui-même s'il n'est pas déjà présent.

### Sur une machine neuve

Ce qui est **automatisé** par `install.sh`/`build.sh` : Homebrew, `jq`, templating des `.plist`, détection d'architecture pour la compilation, vérification des Xcode CLT.

Ce qui reste **manuel**, dans cet ordre :

1. Installer **Tailscale.app** et t'authentifier (`tailscale up`).
2. Accepter l'installation des **Xcode Command Line Tools** si demandé (`xcode-select --install`, popup GUI).
3. Monter chaque partage SMB une première fois à la main pour que macOS enregistre le mot de passe dans le Trousseau (voir Prérequis ci-dessus).
4. Lancer `bash install.sh`.

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
- `launchctl kickstart -k gui/$(id -u)/com.tailscale-nas-watchdog.menubar` — méthode la plus fiable, contourne Finder/Launch Services.
- Sinon, au prochain login/redémarrage, `RunAtLoad` la relance automatiquement.

## Notes de build (si tu recompiles après une mise à jour de macOS)

`build.sh` compile avec `-target <arch>-apple-macosx11.0` (`<arch>` = `arm64` ou `x86_64` selon `uname -m`) et signe le bundle en ad-hoc (`codesign --force --deep --sign -`). Le `-target` explicite est nécessaire : sans lui, `swiftc` embarque par défaut la version du SDK installé (28.0 sur cette machine, plus récente que l'OS réellement installé en 27.0), ce qui fait planter le lancement via Finder avec *"Impossible d'utiliser cette version de l'application avec cette version de macOS"* — le lancement direct (`launchctl`) contournait ce contrôle, mais pas Finder. Fixer la version macOS du `-target` à 11.0 élimine le problème avec une large marge, pas besoin d'ajuster à chaque mise à jour de macOS.

Sans signature ad-hoc, Finder refuse carrément de lancer l'app (icône barrée d'un signe interdit), même sans flag de quarantine — Gatekeeper sur cette bêta semble plus strict que d'habitude pour les apps locales non signées.

## Vérifications

```bash
# Les deux LaunchAgents sont chargés ?
launchctl list | grep tailscale-nas-watchdog

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
bash uninstall.sh
```

Décharge et supprime les deux LaunchAgents (+ les anciens `fr.arnaud.*` s'ils traînent encore), supprime l'app et les logs. Par défaut, **`hosts.json` est conservé** (au cas où tu réinstalles plus tard) ; pour tout purger y compris ta config de serveurs :

```bash
bash uninstall.sh --purge
```

Les volumes déjà montés et les identifiants dans le Trousseau ne sont pas touchés — démonte-les et retire-les toi-même si besoin.

## Comportement

- Toutes les **60 secondes**, le watchdog vérifie Tailscale + chaque serveur listé dans `hosts.json`.
- Si Tailscale n'est pas `Running` et qu'aucune ré-authentification n'est requise → tentative de reconnexion (`tailscale up`).
- Si un serveur est joignable mais pas monté → montage.
- Tant qu'un volume est monté (celui d'un host suivi dans `hosts.json`, ou n'importe quel autre partage SMB monté sous `/Volumes` — par exemple "Films" ou "homes" atteint en parcourant le NAS depuis le Finder), un fichier `.metadata_never_index` est maintenu à sa racine pour désactiver l'indexation Spotlight dessus (pas besoin de `mdutil`/sudo — utile car Spotlight n'a rien à faire sur des partages réseau, et surtout pas sur celui utilisé pour Time Machine). **C'est l'app menu bar qui pose ce flag** (revérifié à chaque rafraîchissement, ~5s), pas `watchdog.sh` : un processus `launchd` sans interface ne peut pas obtenir l'autorisation macOS "Fichiers et dossiers → Volumes réseau" (macOS n'a aucun moyen de lui présenter le pop-up de consentement, donc l'écriture est refusée silencieusement). `watchdog.sh` tente quand même le `touch` en best-effort (ça fonctionne si tu le relances à la main depuis le Terminal, qui a déjà cette permission) mais ce n'est pas fiable en tâche de fond — **l'app menu bar doit tourner** pour que le flag soit posé de façon fiable. Les partages non listés dans `hosts.json` sont aussi listés dans le menu, sous "Autres partages montés (non suivis)" (pas de remontage automatique pour ceux-là, juste affichage + flag Spotlight).
- Si un partage est monté mais que le serveur n'est plus joignable → démontage forcé (montage fantôme nettoyé), puis remontage dès que possible.
- Log dans `~/Library/Logs/TailscaleNAS/watchdog.log`, réinitialisé à chaque redémarrage du Mac (détecté via `sysctl kern.boottime`, comparé à `~/Library/Application Support/TailscaleNAS/.last_boot` — donc un simple `launchctl kickstart`/reinstall ne le vide pas, seul un vrai reboot le fait), et sinon rotation automatique au-delà de ~5 Mo dans la même session.
- Si une sauvegarde Time Machine est en cours (`tmutil status`), un `caffeinate -s -i` est maintenu actif pour bloquer la veille système ; son PID est suivi dans `~/Library/Application Support/TailscaleNAS/.caffeinate.pid` et il est arrêté dès que la sauvegarde se termine.
- L'app ne peut tourner qu'en une seule instance à la fois (elle se ferme toute seule si une autre copie est déjà lancée — évite les doublons d'icône si tu double-cliques dessus alors que le LaunchAgent la fait déjà tourner).
