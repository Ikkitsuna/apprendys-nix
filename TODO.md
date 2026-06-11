# Apprendys V2 — NixOS — Roadmap & TODO

> État bureau : XFCE fonctionnel, panel noir, 3 icônes propres, Greybird, Luciole.
> VM dev : 10.1.0.26 | V1 référence : 10.1.0.27 | Proxmox : 10.1.0.20

---

## 🏛️ Architecture V2 — DÉCISION ARCHITECTURALE FINALE

### Principe fondateur : **Le moins possible la clé USB**

Une clé USB c'est ~1.5 MB/s en 4K random. Toute l'archi doit minimiser les hits sur la NAND
(lectures comme écritures). Trois mécanismes complémentaires :

1. **SquashFS demand-paged** (lectures système) — la clé est lue UNE FOIS au boot, le reste vit dans le page cache Linux
2. **Impermanence + tmpfs** (écritures système volatiles) — tout ce qui n'est pas explicitement persisté part en RAM
3. **GnuRAMage** (écritures userland actives) — `/home/apprendys` en tmpfs, sync sélective vers P4 toutes les 180s
4. **ZRAM swap** — swap compressé en RAM, zéro écriture sur la clé (obligatoire)

### Layout partitions V2 final

```
Clé USB 64 Go (GPT)
├── P1   1 MB   BIOS Boot     → GRUB legacy
├── P2   1 GB   FAT32 EFI     → kernel, initrd, GRUB EFI/Legacy
├── P3   6 GB   ext4          → contient le SquashFS NixOS (immuable, demand-paged)
├── P4  15 GB   ext4          → persistance + overlay /nix/store + patches userland
└── P5  ~42 GB  NTFS DEVOIRS  → fichiers enfant, visible Windows (Couche 3 V1)
```

### Modèle 2 couches d'OTA — "Le beurre et l'argent du beurre"

```
┌─────────────────────────────────────────────────────────────┐
│ COUCHE A — Patches légers (style V1, git pull → rsync /)    │
│                                                             │
│ Repo : github.com/Ikkitsuna/apprendys-patches               │
│ Path : /mnt/apprendys/patches/ → rsync vers /               │
│                                                             │
│ Pour : tutos HTML, configs XFCE, scripts .sh, icônes,       │
│        polices, .desktop launchers, Firefox policies.json,  │
│        LireCouleur .xcu, prompts vocaux                     │
│                                                             │
│ Coût : ~50 Ko, 2 secondes                                   │
│ Fréquence : tous les jours sans souci                       │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ COUCHE B — MAJ système (nixos-rebuild atomique)             │
│                                                             │
│ Repo : github.com/Ikkitsuna/apprendys-nix                   │
│ Path : overlay /nix/store sur P4 (UPPER ext4)               │
│                                                             │
│ Pour : ajout/maj app (Xournal++, Vosk), upgrade kernel,     │
│        patches de sécu CVE, nouvelle voix Piper,            │
│        librairie système                                    │
│                                                             │
│ Coût : 50-500 Mo selon delta                                │
│ Fréquence : selon besoin (CVE, feature)                     │
│ Rollback : natif NixOS (générations)                        │
└─────────────────────────────────────────────────────────────┘
```

**Workflow quotidien Florent :**

| Action | Commande | Effet sur la clé |
|--------|----------|------------------|
| Modifier un tuto / script / icône | `git push` sur apprendys-patches | rsync léger au prochain WiFi |
| Ajouter une app / patch sécu | `git push` sur apprendys-nix | nixos-rebuild atomique, rollback natif |

### Architecture filesystem cible

```
P3 SquashFS RO  ← NixOS complet, demand-paged en RAM (Couche 1 V1 équivalent)
       ↓ overlayfs
P4 ext4 RW      ← /nix/store UPPER (OTA Couche B)
                + impermanence dirs (home, NM, BT, machine-id)
                + /mnt/apprendys/patches/ (OTA Couche A)
                + Vosk/Piper models (option : déportés pour upgrade sans rebuild)
P5 NTFS         ← DEVOIRS (Couche 3 V1)
```

GnuRAMage tourne dans la couche userland (`/home/apprendys` → tmpfs avec sync sélective vers P4).

### Choix outil de build : nixos-generators format `iso`

```nix
inputs.nixos-generators = {
  url = "github:nix-community/nixos-generators";
  inputs.nixpkgs.follows = "nixpkgs";
};

packages.x86_64-linux.usb-image = nixos-generators.nixosGenerate {
  format = "iso";  # ← SquashFS + casper-style boot
  modules = [ ./modules/base.nix ./hardware/usb-key.nix ... ];
};
```

`format = "iso"` génère un SquashFS demand-paged → identique architecture V1.

---

## 🔴 CRITIQUE — Refonte architecturale V2 (BLOQUANT)

### Refonte du flake et du build
- [ ] Ajouter `nixos-generators` aux inputs du `flake.nix`
- [ ] Créer 4 sorties `packages.x86_64-linux` :
  - `apprendys-light-iso` (format `iso`, SquashFS, profil light)
  - `apprendys-pro-iso` (format `iso`, SquashFS, profil pro)
  - `apprendys-ecole-iso` (format `iso`, SquashFS, profil école)
  - `apprendys-dev-vm` (format `qcow`, VM dev existante)
- [ ] Tester `nix build .#apprendys-light-iso` → ISO bootable

### Refonte du hardware/usb-key.nix
- [ ] Supprimer le mount ext4 RO sur `/nix` (faux modèle)
- [ ] Le remplacer par : SquashFS lu depuis P3 + overlay /nix/store sur P4
- [ ] Garder mount P4 ext4 → `/mnt/apprendys` (persistance + overlay UPPER)
- [ ] Garder mount P5 NTFS → `/mnt/devoirs` avec `remove_hiberfile` + fallback RO
- [ ] Configurer GRUB dual UEFI/Legacy (validé V1 sur Blackview Insyde 2015)

### Décision : Impermanence vs GnuRAMage
- [ ] **Garder les deux** mais avec rôles distincts :
  - `modules/persistence.nix` (impermanence) → couche système (NM, BT, machine-id)
  - `modules/gnuramage.nix` → couche userland active (`/home/apprendys` tmpfs + sync 180s)
- [ ] Réécrire `modules/gnuramage.nix` :
  - tmpfs pour `/home/apprendys/.config`, `.mozilla`, `.local`
  - Whitelist sync vers P4 : XFCE config, WiFi, BT, icons custom
  - Exclure : modèles IA, logs, caches gros
  - Détection RAM auto (`/proc/meminfo`) → ajuster périmètre 4/6/8 Go

### Service OTA Couche A (patches V1-style)
- [ ] Créer `modules/ota-patches.nix` :
  - Service NM dispatcher : au WiFi up, `git pull` apprendys-patches
  - Vérification année système (skip si < 2025, pile CMOS morte)
  - Test portail captif via curl sur raw.githubusercontent.com/VERSION
  - Flag `.update_in_progress` (pas critique vu rollback natif côté B)
  - `apply.sh` : rsync `patches/` → `/`
  - notify-send "Apprendys mis à jour vX.Y.Z"
- [ ] Créer le repo GitHub `apprendys-patches` (vide ou seed depuis V1)

### Service OTA Couche B (nixos-rebuild)
- [ ] Créer `modules/ota-system.nix` :
  - Service NM dispatcher : au WiFi up, vérifier flake.lock distant vs local
  - Si différent → `nixos-rebuild switch --flake github:Ikkitsuna/apprendys-nix#<channel>`
  - Background, non-bloquant, notify-send
- [ ] Optionnel : cache Nix CF-Informatik974 (cachix ou S3) pour réduire bande passante

### ZRAM (obligatoire)
- [ ] Activer dans `modules/base.nix` :
  ```nix
  zramSwap.enable = true;
  zramSwap.algorithm = "zstd";
  zramSwap.memoryPercent = 50;
  ```

---

## 🔴 CRITIQUE — Scripts terrain V1 à porter

### Scripts TTS/STT (sources prêtes dans `Apprendys/vkey/apprendys-github/patches/usr/local/bin/`)
- [ ] Porter `apprendys-tts.sh` (Piper + espeak-ng fallback) dans la Couche A patches
- [ ] Porter `apprendys-stt.sh` (Vosk + xdotool, toggle ON/OFF) dans la Couche A patches
- [ ] Tester Ctrl+Espace (TTS) et Ctrl+Maj+Espace (STT) sur la VM dev

### Packages IA (Couche B, dans le flake)
- [ ] Packager **Vosk** → `packages/vosk.nix` (fetchurl wheel + modèle small-fr-0.22)
- [ ] Vérifier `piper-tts` dans nixpkgs (probablement présent)
- [ ] Voix Piper `fr-siwis-medium.onnx` :
  - Option 1 : packager dans le store (Couche B)
  - Option 2 : déposer sur P4 (`/mnt/apprendys/models/`) — V1-style, upgrade sans rebuild

### Robustesse terrain (bugs V1 validés Blackview)
À implémenter dans `apprendys-session-init.sh` (Couche A patches) :
- [ ] Pile CMOS morte → skip réseau si `date +%Y < 2025`
- [ ] Touchpad I2C unbind/sleep 0.3/bind (ALPS/Elan vieux PC)
- [ ] Firefox `.parentlock` cleanup (`find ~/.mozilla -name ".parentlock" -delete`)
- [ ] Chromium SingletonLock cleanup
- [ ] Boucle symlink P5/devoirs (`[ -L /mnt/devoirs/devoirs ] && rm`)
- [ ] pavucontrol crash FR → pré-créer `~/.config/pavucontrol.ini`
- [ ] `noprompt` dans GRUB config (supprime "remove installation medium")

---

## 🟠 IMPORTANT — Fonctionnalités V1 manquantes

### LibreOffice — LireCouleur
- [ ] Packager extension LibreOffice (Couche B)
  - Source : `extensions.libreoffice.org/fr/extensions/show/lirecouleur`
  - `packages/lirecouleur.nix` → fetchurl .oxt + dérivation
- [ ] Déployer config V1 (`registrymodifications.xcu`) via Couche A patches :
  - Autosave → `/home/apprendys/Devoirs/autosave`
  - Police Luciole par défaut

### Xournal++ — Autosave robuste
- [ ] Config V1 (`settings.xml`) déployée via Couche A patches :
  - `autosavePath=/home/apprendys/Devoirs/autosave` (toutes les 3 min)
  - `font=Luciole Regular 14`
- [ ] Fallback `/tmp` silencieux si P5 NTFS en RO (Fast Startup Windows)

### Fonts — choix parental sans rebuild
- [ ] Switch Luciole ↔ OpenDyslexic via `~/.config/apprendys/font-name`
  - `session-init` lit le fichier, applique via xfconf-query (Couche A)
  - Recharge GTK immédiat, sans reboot

### Firefox — robustesse
- [ ] DoH désactivé (`network.trr.mode = 5`) — bug V1 timeout DNS scolaire
- [ ] uBlock Origin + Unhook auto via policies.json (Couche A patches)
- [ ] Cache Firefox → `/dev/shm/firefox-cache` (zéro écriture clé)

---

## 🟡 AMÉLIORATION — V2 spécifique

### App Apprendys (GUI personnalisation)
- [ ] App Python/GTK3 `apprendys-control` (Couche B package)
  - Switch profil icônes, fonts, taille police, wallpaper, thème
  - Contrôle parental via PIN
  - Tout via xfconf-query → zéro rebuild
  - Mode Windows depuis P5 : diagnostic clé, lancer MAJ, changer canal

### Onboarding
- [ ] Porter `show-onboarding.py` (GTK3 plein écran) — Couche A patches
- [ ] Déployer 4 tutos HTML V1 dans `/usr/share/apprendys/docs/` (Couche A)
- [ ] Flag `~/.config/apprendys/onboarding_done` pour ne pas réafficher

### Multi-canal (light/pro/école)
- [ ] 3 builds NixOS distincts (un ISO par canal)
  - Cache Nix partagé entre les 3 (la majorité des packages identiques)
- [ ] Canal écrit dans `~/.config/apprendys/.channel` (hors GnuRAMage whitelist)
- [ ] `modules/school.nix` : proxy, filtrage DNS, restrictions

---

## 🟢 OPTIMISATION & ROBUSTESSE

### Performance clé USB
- [ ] `services.journald.storage = "volatile"` — pas de logs persistants sur flash
- [ ] CPU governor adaptatif : `powersave` par défaut, `performance` si secteur
- [ ] Cache navigateurs → `/dev/shm/`

### Sécurité enfant
- [ ] `security.sudo.enable = false` — fait en base.nix ✓
- [ ] `networking.firewall.enable = true` — bloque tout entrant
- [ ] `nix.settings.sandbox = true` — builds isolés
- [ ] DNS filtrage familial (option dans school.nix)

### Build & flash USB
- [ ] Script `flash.sh` :
  - dd ISO sur clé + création P4 ext4 + P5 NTFS
  - Vérification SHA256
  - Refus disques non-USB (sécurité)
- [ ] Tester boot physique sur Kingston Exodia 64 Go (cible prod)
- [ ] Tester sur Kodak (validé V14) + Blackview (BIOS 2015)

### Checklist livraison
- [ ] P5 NTFS DEVOIRS monté (`ls ~/Devoirs/`)
- [ ] Firefox charge correctement
- [ ] TTS/STT fonctionnels (Ctrl+Espace / Ctrl+Maj+Espace)
- [ ] Chromium s'ouvre (SingletonLock absent)
- [ ] Autosave Xournal++ vers Devoirs
- [ ] Ne pas mettre son propre WiFi sur la clé

---

## 📦 PACKAGES À CRÉER

| Package | Source | Couche | Statut |
|---------|--------|--------|--------|
| `luciole` | luciole-vision.com/fonts/Luciole.zip | B (Nix) | ✅ Fait |
| `vosk` | alphacephei.com/vosk | B (Nix) | ⬜ |
| `vosk-model-fr` | alphacephei.com (small-fr-0.22) | B ou P4 | ⬜ |
| `piper-tts` | github.com/rhasspy/piper | B (vérifier nixpkgs) | ⬜ |
| `piper-voice-fr-siwis` | huggingface.co (siwis-medium.onnx) | B ou P4 | ⬜ |
| `lirecouleur` | extensions.libreoffice.org | B (Nix) | ⬜ |
| `apprendys-control` | À créer (Python GTK3) | B (Nix) | ⬜ |

---

## 📚 SOURCES DE VÉRITÉ V1

| Document | Chemin local | Contenu |
|----------|-------------|---------|
| Architecture PDF | `Apprendys/vkey/Apprendys_Architecture_v13.docx.pdf` | Vision 3 couches, GnuRAMage, OTA |
| CLAUDE.md V1 | `Apprendys/vkey/apprendys-github/CLAUDE.md` | Guide complet dev V1 (1.0.29) |
| STATE.md | `Apprendys/vkey/STATE.md` | État V14, bugs terrain validés |
| ZERO-TO-HERO.md | `Apprendys/vkey/ZERO-TO-HERO.md` | Journal de build complet |
| ROADMAP.md | `Apprendys/vkey/ROADMAP.md` | Roadmap V1.1/V1.2/V2 |
| Scripts V1 | `Apprendys/vkey/apprendys-github/patches/` | TTS, STT, session-init, gnuramage |

---

## ✅ FAIT

### 🚀 V2 PHASE 1 — Premier ISO bootable validé (2026-05-07 18:08)

- [x] **Flake refondu avec nixos-generators** (4 sorties : 3 ISO + 1 VM dev)
- [x] **Build ISO réussi** : `nixos-26.05.20260427.1c3fe55-x86_64-linux.iso` (3.0 GB)
- [x] **Boot UEFI validé en VM Proxmox 105** : ISO démarre en SquashFS demand-paged
- [x] **Bureau XFCE Apprendys live** : wallpaper, 3 icônes, panel noir, Luciole, autologin → tout opérationnel
- [x] **ZRAM activé** + tmpfs /tmp + journald volatile + swappiness=0 dans base.nix
- [x] **GnuRAMage refondu** en module userland opt-in (`apprendys.gnuramage.enable`)
- [x] **packages/apprendys-tts.nix** créé (wrapper script avec piper-tts + espeak fallback)
- [x] Screenshot V2 first boot : `assets/v2-first-boot-success.png`

### Bureau V2 (déjà fait avant)

- [x] Bureau XFCE : 3 icônes propres (Mes Devoirs, Mes Leçons, Je Recherche)
- [x] Panel noir, layout V1 exact
- [x] Thème GTK Greybird
- [x] Icônes elementary-xfce
- [x] Font Luciole installée et active
- [x] Font OpenDyslexic en fallback
- [x] Wallpaper V1 nuages bleus
- [x] Screensaver / DPMS désactivés
- [x] Keyboard shortcuts TTS/STT bindings
- [x] Trust desktop .desktop XFCE 4.18 (sha256 + chmod 755)
- [x] Taille menu Whisker dynamique (45% via xrandr)
- [x] Fond panel forcé via session-init
- [x] Modules : base, apps, accessibility (stub), dev-vm
- [x] Home Manager : apprendys.nix complet
- [x] VM dev 10.1.0.26 fonctionnelle
- [x] Documents V1 récupérés depuis Proxmox
- [x] **Décision archi V2 : SquashFS + overlay /nix/store + 2 couches OTA** (2026-05-XX)

---

## 🚧 PROCHAINE SESSION

Phase 1 ✅ ISO bootable. Ordre d'attaque pour la suite :

1. **Persistence sur clé physique** :
   - Adapter `hardware/usb-key.nix` pour la phase post-flash (P4 ext4 + P5 NTFS montés via service)
   - Réintégrer `modules/persistence.nix` (impermanence) dans `usbModules` du flake
   - Réintégrer `modules/gnuramage.nix` avec activation conditionnelle (option `apprendys.gnuramage.enable = true` dans profils USB)
   - Créer service systemd qui crée P4/P5 si absentes (premier boot post-dd)

2. **Service OTA Couche A** (patches V1-style) :
   - `modules/ota-patches.nix` : NM dispatcher → git pull /mnt/apprendys/.repo → apply.sh
   - `apply.sh` adapté NixOS (pas de rsync sur /usr, scope limité à /var/lib/apprendys/* + /home)
   - Repo GitHub `apprendys-patches` à créer (vide ou seed depuis V1)

3. **Service OTA Couche B** (nixos-rebuild) :
   - `modules/ota-system.nix` : NM dispatcher → check flake.lock distant → rebuild si changé
   - Cache Nix CF-Informatik974 (cachix ou S3) pour réduire bande passante

4. **Scripts terrain V1 portés** :
   - Inclure `apprendys-tts` dans systemPackages (apps.nix)
   - Packager Vosk Python (wheel) + modèle FR small → packages/vosk.nix
   - Créer apprendys-stt wrapper (besoin Vosk d'abord)
   - Packager voix Piper fr-siwis-medium.onnx → packages/piper-voice-fr.nix
   - apprendys-session-init.sh → service NixOS (CMOS, parentlock, SingletonLock, touchpad I2C)

5. **Flash physique** :
   - Script `flash.sh` : dd ISO + création P4 ext4 + P5 NTFS + vérif SHA256
   - Test sur Kingston Exodia 64Go (cible prod)
   - Test BIOS legacy + UEFI
