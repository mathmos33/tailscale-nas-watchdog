# Handoff notes

Ce projet a été déplacé de iCloud Drive vers `~/Developer/tailscale-nas-watchdog`
(git + iCloud Drive ne fait pas bon ménage). Le repo GitHub (`mathmos33/tailscale-nas-watchdog`)
reste le mécanisme de synchro entre le MacBook Pro et l'iMac — chaque machine a
son propre clone local, en dehors d'iCloud.

## Pour reprendre le travail (nouvelle session Claude Code)

Cette session-ci reste bloquée sur l'ancien chemin iCloud (c'est là qu'elle a
été lancée) et ne peut pas être redirigée en cours de route. Pour repartir du
bon dossier :

```
cd ~/Developer/tailscale-nas-watchdog
claude
```

Le dossier a déjà son propre `.claude/settings.local.json` (permissions), donc
rien d'autre à configurer.

L'ancien dossier iCloud (`.../Projets/Claude (misc and refs)/tailscale-nas-watchdog`)
ne contient plus que les settings de cette session-ci ; il peut être supprimé
une fois cette session fermée.

## État au 14 août

Repo à jour avec `origin/main`. Correctifs livrés :
- `23ba97e` — bug d'extraction du point de montage SMB pour les partages avec
  espaces dans le nom (ex. "Series 4K UHD") : le flag `.metadata_never_index`
  n'était jamais écrit.
- `c2b0812` — signature avec un certificat local stable au lieu d'ad-hoc, pour
  que les autorisations TCC (Network Volumes) survivent aux rebuilds.
- `2492fc8` — cache de confirmation Spotlight par point de montage **côté app
  menu bar**, pour arrêter les appels réseau SMB toutes les 5s qui causaient
  une latence système (délai avant double-clic).
- Session du 14 août — même classe de bug que `2492fc8` repérée côté
  `watchdog.sh` : le script re-statait `.metadata_never_index` sur les 5
  partages montés à chaque cycle de 60s (pas de cache, contrairement à l'app
  Swift), assez pour geler occasionnellement le Finder de façon system-wide
  (session SMB partagée). Preuve dans `watchdog.log` : écarts de 1-3s entre
  le traitement de deux hosts dans un même cycle, dérive de l'intervalle
  60s → 61-67s. Fix : cache sur disque
  (`~/Library/Application Support/TailscaleNAS/.spotlight_confirmed`),
  vidé à chaque vrai reboot comme le log. README mis à jour en conséquence
  (+ ajout de `README.en.md`, traduction anglaise à garder synchronisée) ;
  `HANDOFF.md` supprimé (doublon de ce fichier).

## État au 22 août

Install testée de zéro sur un MacBook Air (Brigitte, Sonoma 14.8, Intel).
Correctifs livrés :
- `9d2b727` — deux bugs distincts qui bloquaient l'install sur cette machine :
  - **CLT 15.3 casse toute compilation** : bug de packaging Apple connu
    (`redefinition of module 'SwiftBridging'`, modulemap dupliqué), et son
    `swiftc` (Swift 5.10) est de toute façon trop vieux pour parser le SDK
    d'une install CLT 16.2 partielle (`unknown attribute '_extern'`). `build.sh`
    vérifie maintenant `swiftc --version` et s'arrête avec un message clair
    (réinstall CLT 16.2 via `softwareupdate`, pas de sudo caché dans
    `install.sh` — cf. discussion : on a délibérément gardé le principe
    "sans sudo" plutôt que d'automatiser l'install des CLT, qui en plus s'est
    montrée peu fiable : la mise à jour auto de macOS a réinstallé la 15.3
    par-dessus la 16.2 12 minutes après coup, en tâche de fond).
  - **`jq` invisible pour le watchdog LaunchAgent** : `command -v jq` marche
    en shell interactif mais `launchd` tourne avec un PATH minimal
    (`/usr/bin:/bin:/usr/sbin:/sbin`), sans les préfixes Homebrew — le
    watchdog échouait à chaque cycle malgré `brew install jq` réussi.
    `TAILSCALE_BIN` avait déjà ce traitement (chemins candidats explicites),
    pas `jq`. Fix : `export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"`
    en tête de `watchdog.sh`.
- `520ee73` — l'app menu bar (`LSUIElement`/`.accessory`) n'avait jamais de
  menu "Édition" : ⌘C/⌘V/⌘X/⌘A ne marchaient pas dans les champs texte de
  Préférences (AppKit ne route ces raccourcis que via un vrai menu Édition
  avec Cut/Copy/Paste/Select All liés aux actions standard). Fix : menu
  construit et assigné à `NSApp.mainMenu` dans `applicationDidFinishLaunching`.
  Vérifié via Accessibility (`osascript`/System Events) que macOS reconnaît
  bien le menu (ajout auto des items système type "Writing Tools").
- README.md / README.en.md mis à jour pour le pré-requis CLT 16.2/Swift 6+
  (synchronisés).

## Point ouvert : montage `homes/lesrybeau.ts` sur l'iMac

Sur l'iMac, `lesrybeau.ts` apparaît deux fois dans le menu : le sous-dossier
`TimeMachine` (suivi, index off — OK) et la racine du partage `homes` (non
suivi, jamais passé en index off, même après plusieurs cycles de refresh).
Probablement un montage créé par `backupd` lors de la validation de la
destination Time Machine réseau. Hypothèse à vérifier : montage
incomplet/instable plutôt que bug de code.

Diagnostic à faire sur l'iMac (commandes à lancer là-bas et à rapporter) :

```
mount | grep -i lesrybeau
ls -la /Volumes/ | grep -i lesrybeau
cat ~/Library/Application\ Support/TailscaleNAS/state.json
```
