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
