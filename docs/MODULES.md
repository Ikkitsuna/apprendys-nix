# Apprendys OS — Référence fichier par fichier

> **But** : pour chaque fichier, son rôle, ses points clés et ce qu'il ne faut **pas**
> casser. Complément de `ARCHITECTURE.md` (modèle mental) et `OPERATIONS.md` (runbook).
> Le code lui-même est très commenté — ce doc est la carte, le code est le territoire.

---

## `flake.nix`
Le chef d'orchestre. Déclare les sorties ISO (`packages.x86_64-linux.*`) et les systèmes
(`nixosConfigurations.*`), et les groupes `commonModules`/`usbModules`. Détaillé dans
`ARCHITECTURE.md` §3. **À lire en premier.**

---

## `profiles/` — QUI est la machine

### `profiles/installed.nix` ⭐ (le produit final)
Le système sur le PC dédié après installation.
- Importe `hardware-quirks.nix` + `ota-installed.nix`.
- **Disques par label** : `/`=`APPRENDYS` (ext4), `/boot`=`APPR-EFI` (vfat). Posés par
  l'installateur → aucun UUID, image portable sur n'importe quel PC.
- **GRUB** : `device="nodev"`, `efiSupport`, `efiInstallAsRemovable=true` (UEFI fragiles),
  `configurationLimit=5` (5 rollbacks OTA).
- `initrd.availableKernelModules` large (vieux matériel inconnu).
- `enableRedistributableFirmware=true` (WiFi des vieux PC).
- journald repassé en `Storage=auto` 200 Mo (disque interne, logs SAV).
- **N'importe PAS `light.nix`** → garde SSH off / sudo off (prod verrouillée).
- 🚫 **Ne change pas les labels** `APPRENDYS`/`APPR-EFI` sans changer aussi l'installateur.

### `profiles/light.nix` (clé live standard + base de l'installeur)
Vieux PC, Vosk small.
- systemd-boot, `configurationLimit=2`.
- Variables `APPRENDYS_STT_MODEL`/`TTS_MODEL`/`PROFILE=light`.
- ⚠️ **Ouvre SSH (`mkForce true`) + sudo NOPASSWD + ajoute `wheel`** : c'est du **debug**.
  C'est `release.nix` qui referme tout ça dans l'ISO livrée. Une ISO `light` seule = ouverte.

### `profiles/pro.nix` (clé live PC récent)
≥8 Go RAM, modèles STT/TTS sur P4. `configurationLimit=3`. Whisper encore à packager (TODO
dans le fichier).

---

## `modules/` — QUOI on active

### `modules/base.nix` ⭐ (le socle, présent partout)
Le plus gros et le plus important après le flake.
- **Locale FR forcée** champ par champ (`LC_*`) — `defaultLocale` ne suffit pas en ISO live
  (Firefox/LibreOffice/GTK lisent `LC_MESSAGES` direct). Clavier AZERTY. TZ `Indian/Reunion`.
- **XFCE + SDDM + autologin `apprendys`**. NetworkManager, PipeWire, Bluetooth.
- **User `apprendys`** : uid 1000, `initialPassword="apprendys"`, **clé SSH debug de Florent**
  (retirée en prod par `release.nix`). sudo off par défaut (`mkDefault`).
- **`apprendys-prenom.service`** : applique le prénom au compte (GECOS via `usermod -c`) au
  boot, avant le display-manager. Lit `~/.config/apprendys/user-name` puis
  `/var/lib/apprendys/user-name`. Déclenchable à chaud par Mon Apprendys via **polkit**.
- **Fonts DYS** : Luciole (maison) en priorité, OpenDyslexic en fallback.
- **Optimisations clé USB** (cf `ARCHITECTURE.md` §8) : ZRAM zstd 50 %, `swappiness=0`,
  journald volatile 64 Mo, `/tmp` tmpfs, flush dirty pages 60 s.
- `system.stateVersion="24.11"`. 🚫 **Ne touche jamais au stateVersion** d'un système déployé.

### `modules/apps.nix` ⭐ (tout le userland applicatif)
Empaquète et installe les logiciels + leurs politiques.
- Câble les packages maison : `apprendys-tts`, `apprendys-stt`, `apprendys-session-init`,
  `apprendys-app`, voix Piper, modèle Vosk, LireCouleur (via `callPackage`).
- `system.extraDependencies` + `environment.pathsToLink` pour forcer l'inclusion des données
  `share/`-only (voix, modèle, lirecouleur) que l'image ISO n'embarque pas par défaut.
- Apps : Xournal++ (Mes Devoirs), LibreOffice (Mes Leçons + LireCouleur), Firefox/Chromium
  (Je Recherche), dicos FR, outils XFCE.
- **Politique Firefox** : UI FR forcée, télémétrie/comptes off, **uBlock + Unhook** (pas de
  recommandations YouTube toxiques) en `force_installed`, page d'accueil verrouillée.
- **Politique Chromium** : recherche par défaut **Ecosia**, téléchargements → `~/Devoirs`.

### `modules/accessibility.nix`
Le squelette TTS/STT. Les raccourcis (Ctrl+Espace = TTS, Ctrl+Maj+Espace = STT) sont en fait
définis dans `home/apprendys.nix` (xfconf). Active AT-SPI. Les vrais scripts sont les packages
`apprendys-tts`/`apprendys-stt` câblés dans `apps.nix`.

### `modules/installer.nix` ⭐ (présent dans l'ISO installeur uniquement)
Branche l'installateur 3-clics.
- Embarque la **closure complète** du système installé dans l'ISO
  (`system.extraDependencies = [ installedSystem ]`) → `nixos-install` **100 % offline**.
- Met l'icône « Installer Apprendys » sur le Bureau.
- **Règle sudo NOPASSWD dédiée** au seul binaire `apprendys-installer`, sur **deux chemins**
  (le symlink `/run/current-system/sw/bin/...` réellement utilisé + le chemin store).
  Raison : `command -v` renvoie le symlink, et sudo matche le chemin EXACT tapé.
- 🚫 Point délicat : ne change pas la façon dont le script se ré-élève sans relire ce commentaire.

### `modules/ota-installed.nix` ⭐ (la maintenance du parc)
La mise à jour automatique. Détaillé dans `ARCHITECTURE.md` §6 et `OPERATIONS.md` §4.
- Timer hebdo `Persistent=true`, `nixos-rebuild switch --flake github:Ikkitsuna/apprendys-nix?ref=main#apprendys-installed`.
- **Garde-fou année < 2026** (pile CMOS morte → SSL cassé → on saute).
- Bouton « Vérifier maintenant » via **polkit** (start de `apprendys-ota.service` par `apprendys`).
- 🚫 Une `main` qui ne compile pas **bloque l'OTA de tout le parc** : tester avant de pousser.

### `modules/release.nix` ⭐ (durcissement de l'ISO LIVRÉE)
Le « referme tout » de la prod. Présent **uniquement** dans `apprendys-installer-iso`.
- `lib.mkOverride 40` (prio plus haute que `mkForce` 50) écrase les ouvertures debug de
  `light.nix` : **SSH off**, **sudo password**, **clé debug retirée**, **`wheel` retiré**.
- 🚫 C'est ce fichier qui rend l'ISO sûre à livrer. L'ISO `…-sshtest` ne l'a pas → **jamais livrée**.

### `modules/hardware-quirks.nix`
Rustines vieux matériel. Aujourd'hui : **rebind du touchpad I2C** (ALPS/Elan) mort après warm
boot (unbind/sleep/bind). Bug terrain V1, validé Blackview. C'est le bon endroit pour ajouter
d'autres quirks PC.

### `modules/persistence.nix` (clé USB, via `impermanence`)
Sur la **clé nomade**, `/` est en tmpfs (RAM) ; ce module déclare ce qui **survit** sur P4
(`/mnt/apprendys/persist`) : `/home/apprendys`, connexions WiFi NM, Bluetooth, `/etc/machine-id`.
⚠️ Actuellement **commenté dans le flake** (`usbModules`) — à réintégrer après refonte hardware.

### `modules/gnuramage.nix` (clé USB, désactivé par défaut)
Couche userland alternative : `/home/apprendys` en tmpfs + **sync sélective** (whitelist :
config XFCE, profil Firefox, prefs apprendys…) vers P4 toutes les 180 s + sync au shutdown.
Protège la NAND. Activable via `apprendys.gnuramage.enable = true`. ⚠️ Si actif, impermanence
ne doit PAS persister `/home/apprendys` (conflit). Commenté dans le flake aussi.

### `modules/school.nix` (ajouté au profil `ecole`)
Squelette : proxy HTTP, DNS interne, `APPRENDYS_CHANNEL=ecole` (canal MAJ séparé). La plupart
des options sont en commentaires à activer selon l'établissement.

### `modules/dev-vm.nix` (VM de dev uniquement)
Diffère de la prod : **SSH on**, user **`florent`** (sudo NOPASSWD), qemu-guest-agent (Proxmox),
systemd-boot, paquets dev (git, vim, nix-tree…). VM ApprendysV2-Dev sur **`10.1.0.26`**.

---

## `home/apprendys.nix` ⭐ (la session XFCE, home-manager)
Tout l'aspect « bureau » de l'utilisateur.
- Wallpapers (enfant/adulte), icône menu Whisker, **3 sets d'icônes** (junior/teen/adult).
- **Icônes Bureau** FR (Mes Devoirs/Je Recherche/Mes Leçons) + lanceurs panel (Lis-Moi/Je
  Dicte/Mes Fichiers).
- `xdg.userDirs` : Bureau + **Devoirs** comme dossier Documents/Téléchargements.
- **Bloc `home.activation.xfceConfig`** : écrit DIRECTEMENT les XML xfconf (panel, raccourcis
  clavier dont Ctrl+Espace→TTS, fenêtres, fond, screensaver **désactivé**, power manager **pas
  de veille**). Raison : `xfconf-query --create` ne met pas à jour les propriétés existantes →
  on écrase les fichiers XML lus au démarrage de session.
- Thème GTK Greybird, police Luciole 13, marque-page « Mes Devoirs » dans tous les dialogues.
- Autostart de `apprendys-session-init`.
- 🚫 `force=true` sur les `.desktop` est volontaire (écrase les fichiers pré-existants des
  systèmes migrés). Le panel est écrit en vrais fichiers (pas symlinks) pour éviter les
  doublons numérotés de xfce4-panel.

---

## `hardware/` — le matériel réel (généré, pas écrit à la main)

### `hardware/usb-key.nix` ⭐ (layout des 5 partitions de la clé)
Le plan de la clé nomade :
- **P1** BIOS boot (1 Mo) · **P2** `APPR-BOOT` (1 Go FAT32, EFI) · **P3** `APPRENDYS-OS`
  (6 Go ext4, **Nix store en ro+noatime**) · **P4** `APPRENDYS` (15 Go ext4, persistance,
  monté `/mnt/apprendys`) · **P5** `DEVOIRS` (reste, **NTFS** visible Windows, automount).
- `/` en tmpfs 2 Go. Kernel `quiet splash loglevel=0` (boot propre).
- ⚠️ Ne pas confondre avec le layout de l'**installateur** (3 partitions GPT : BIOS/ESP/ROOT)
  — la clé et le PC installé n'ont pas le même schéma.

### `hardware/dev-vm.nix`
`hardware-configuration.nix` généré de la VM libvirt locale (disques par UUID, qemu-guest).
Reflet fidèle de la VM — ne pas éditer à la main.

---

## `packages/` — AVEC QUOI (logiciels maison)

| Package | Rôle | Notes |
|---|---|---|
| **`apprendys-installer.nix`** ⭐ | Le script des « 3 clics » : zenity (avertissement → choix disque → prénom/style → confirmation) puis partitionnement GPT + `nixos-install` offline + GRUB (UEFI auto / legacy manuel) + écriture prénom/profil dans `/var/lib/apprendys`. | Exclut l'USB live (`TRAN=usb`), loop, sr, zram. Log : `/tmp/apprendys-install.log`. Aucun retry. Labels `APPRENDYS`/`APPR-EFI`. **Cœur du produit — voir le code, très commenté.** |
| **`apprendys-session-init.nix`** ⭐ | Lancé à **chaque login** XFCE (autostart). Seed `~/.config/apprendys/` depuis `/var/lib/apprendys` (1er login), applique le set d'icônes + l'ambiance (enfant clair / adulte sombre), installe LireCouleur (1×), nettoie locks stale, « trust » les .desktop Bureau, wallpaper dynamique, taille menu Whisker selon résolution, précharge le modèle Vosk (dictée instantanée), seed autosave LibreOffice/Xournal++. | `set +e` partout (ne crashe jamais la session). Le réglage police de l'utilisateur (Mon Apprendys) prime sur l'ambiance. |
| **`apprendys-app.nix`** + `apprendys-app/apprendys-app.py` ⭐ | **« Mon Apprendys »** : l'appli de réglages (styles Mignon/Classique/Monochrome, police Luciole/OpenDyslexic + taille, curseur) + **espace parent (PIN)** + bouton mise à jour OTA. GTK/Python. | Écrit dans `~/.config/apprendys/` (font-style, font-size, icon-set, user-name). Déclenche `apprendys-prenom`/`apprendys-ota` via polkit (pas de sudo). |
| `apprendys-tts.nix` | **Lis-Moi** : lit la sélection avec Piper (voix FR siwis), fallback espeak. Raccourci Ctrl+Espace. | Pas un daemon : lancé à la demande. |
| `apprendys-stt.nix` | **Le Perroquet / Je Dicte** : dictée vocale offline Vosk. Ctrl+Maj+Espace. | Modèle préchargé au login par session-init. |
| `piper-voice-fr-siwis.nix` | Voix FR Piper (~80 Mo), validée terrain V14. | |
| `vosk.nix` / `vosk-model-fr-small.nix` | Moteur STT + modèle FR small (~50 Mo, baked dans le store). | |
| `lirecouleur.nix` | Extension LibreOffice (colorisation syllabes/sons). | Installée par session-init (`unopkg`). |
| `luciole.nix` | **Police DYS Luciole** (maison CF-Informatik974). | Police par défaut de tout l'OS. |

---

## `assets/` (données statiques)
Wallpapers (enfant/adulte), icônes (junior/teen/adult + menu), guides **utilisateur** HTML
(`assets/guides/` : démarrage WiFi, micro, devoirs, LireCouleur) servis dans l'OS. C'est de la
data, pas du code.

---

## `docs/superpowers/plans/`
Plans d'implémentation superpowers (`2026-06-11-mvp-apprendys-installed.md` + `EXECUTION-STATUS.md`)
et captures de preuve de boot. Historique de construction, pas de la doc de référence.

---

## Récapitulatif « ne casse jamais ça »
1. Labels `APPRENDYS` / `APPR-EFI` : en dur dans `installed.nix` ET l'installateur — change les deux ensemble.
2. `release.nix` doit être dans l'ISO livrée ; ne jamais livrer `…-sshtest`.
3. `main` doit toujours compiler (`nix build …apprendys-installed`) sinon OTA cassé pour tout le parc.
4. `stateVersion` d'un système déployé : on n'y touche pas.
5. La logique d'exclusion de l'USB dans l'installateur (`TRAN=usb`/loop/sr/zram) : ne pas modifier sans test VM.
6. Repo **public** : zéro secret/clé privée.
