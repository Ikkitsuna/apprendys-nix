# Apprendys OS — Architecture

> **But de ce document** : le modèle mental complet pour reprendre la main à tout
> moment. Si tu reviens sur le projet après des mois, lis ça en premier.
> Projet : **CF-Informatik974** (La Réunion). Base : **NixOS** (flake).

---

## 1. L'idée en une page

Apprendys transforme un PC (même vieux) en un ordinateur **dédié, épuré, hors-ligne**
pour enfants/adultes DYS-TDAH-TSA. Tout est déclaré en **NixOS** : la config EST le
système. On ne « bricole » pas une machine, on **décrit** un système et Nix le construit
à l'identique, à chaque fois.

Conséquence directe pour toi : **rien n'est caché dans un état mutable**. Tout ce que fait
l'OS est écrit dans les fichiers `.nix` du repo. Pour comprendre un comportement, tu lis le
module correspondant. Pour le changer, tu édites le module et tu rebuild.

Le **produit vendu** = une **clé USB installateur « 3 clics »** : on branche sur le vieux PC,
on clique « Installer Apprendys », ~20 min plus tard le PC est devenu l'ordinateur de l'enfant.
100 % hors-ligne (la clé embarque tout le système à installer).

---

## 2. Les 3 couches du dépôt : profiles / modules / packages

C'est LA distinction à avoir en tête. Du plus général au plus spécifique :

```
flake.nix          ← le chef d'orchestre : déclare quoi construire
  │
  ├── profiles/    ← QUI est la machine (une variante = un profil)
  │     installed.nix  light.nix  pro.nix     (+ school via module)
  │
  ├── modules/     ← QUOI active-t-on (briques de config réutilisables)
  │     base, apps, accessibility, installer, ota-installed, release,
  │     hardware-quirks, persistence, gnuramage, school, dev-vm
  │
  └── packages/    ← AVEC QUOI (logiciels maison empaquetés pour Nix)
        apprendys-app, apprendys-installer, apprendys-tts, apprendys-stt,
        apprendys-session-init, vosk, piper-voice…, lirecouleur, luciole
```

- **Un profil** = un point d'entrée qui décrit une machine cible (le PC installé, la clé
  light, la clé pro). Il importe des modules et fixe quelques réglages (bootloader, modèle
  STT, variables d'env).
- **Un module** = une brique de configuration NixOS (un service, des réglages, une règle
  polkit…). Réutilisable par plusieurs profils.
- **Un package** = un logiciel empaqueté (souvent maison : l'app de réglages, les scripts
  TTS/STT, l'installateur). Référencé par les modules via `pkgs.callPackage`.

Règle mentale : **profil = la personne, module = ce qu'elle sait faire, package = ses outils.**

---

## 3. `flake.nix` — le chef d'orchestre (à connaître par cœur)

`flake.nix` ne « fait » rien tout seul : il **déclare des sorties**. Deux familles :

### a) `packages.x86_64-linux.*` — les ISO (flashables sur clé via `dd`)

| Sortie | Profil | Pour quoi |
|---|---|---|
| `apprendys-light-iso` | `light` | Clé live standard — vieux PC, Vosk small, ≥4 Go RAM |
| `apprendys-pro-iso` | `pro` | Clé live — PC récent, Whisper, ≥8 Go RAM |
| `apprendys-ecole-iso` | `light` + `school.nix` | Clé école (proxy + restrictions) |
| **`apprendys-installer-iso`** | `light` + `installer` + `release` | **LE produit** : installe Apprendys sur le PC, 100 % offline |
| `apprendys-installer-iso-sshtest` | idem **sans** `release` | Test/CI uniquement (SSH ouvert) — **ne jamais livrer** |
| `default` | `light` | Alias de `nix build` sans cible |

Les ISO sont générées par **`nixos-generators`** (`format = "iso"`), en SquashFS demand-paged.

> **Le tour de magie de l'installateur offline** : `apprendys-installer-iso` reçoit en
> `specialArgs` le **système installé complet** (`installedSystem` =
> `nixosConfigurations.apprendys-installed…system.build.toplevel`) et l'embarque dans l'ISO
> via `system.extraDependencies`. Du coup `nixos-install` chez le client **n'a besoin
> d'aucun réseau** : toute la closure est déjà sur la clé.

### b) `nixosConfigurations.*` — des systèmes NixOS (pas des ISO)

| Config | Rôle |
|---|---|
| **`apprendys-installed`** | Le système qui tourne sur le PC dédié après installation. **C'est la cible de l'OTA et de l'installateur.** |
| `apprendys-dev` | VM de développement (NixOS classique sur disque virtuel, qu'on `nixos-rebuild` en place) |

### c) Les regroupements de modules (en haut du `flake.nix`)

- `commonModules` = `base.nix` + `apps.nix` + `accessibility.nix` + home-manager (session
  `apprendys`). **Présent dans TOUTES les variantes.**
- `usbModules` = `impermanence` (et, commentés, `persistence`/`gnuramage` à réintégrer après
  refonte hardware). Pour les builds clé/ISO.
- `mkApprendysIso { profile, extraModules }` = la petite fonction qui assemble
  `commonModules + usbModules + profile + extraModules` en une ISO.

**Si tu ne lis qu'un fichier pour comprendre le projet : c'est `flake.nix`.**

---

## 4. Anatomie d'une machine installée (`apprendys-installed`)

C'est la machine qui compte (le produit final). Sa config =
`commonModules` + `profiles/installed.nix`, lequel importe `hardware-quirks.nix` +
`ota-installed.nix`.

Points structurants (tous dans `profiles/installed.nix` + `modules/base.nix`) :

- **Disques par label, pas par UUID** : `/` = `/dev/disk/by-label/APPRENDYS`,
  `/boot` = `/dev/disk/by-label/APPR-EFI`. C'est l'installateur qui pose ces labels exacts
  → aucun UUID machine-spécifique, la même image marche sur n'importe quel PC.
- **Bootloader GRUB** (et pas systemd-boot ici) : `device = "nodev"`, `efiSupport`,
  `efiInstallAsRemovable = true` (pas d'écriture NVRAM, pour les vieux UEFI fragiles),
  `configurationLimit = 5` (→ 5 générations au menu = 5 niveaux de rollback OTA).
- **initrd large** (`ahci sd_mod nvme xhci_pci ehci_pci usb_storage ata_piix isci…`) :
  matériel inconnu à l'avance (vieux portables 2005-2015).
- **Firmware redistribuable activé** : la WiFi est souvent le seul réseau des vieux PC.
- **Prod = verrouillé** : SSH off, sudo off (défauts de `base.nix`). `installed.nix`
  n'importe **pas** `light.nix` (qui, lui, ouvre SSH/sudo pour le debug).

---

## 5. Le flux de boot & de session (qui lance quoi)

```
GRUB ──► noyau + initrd ──► systemd
  │
  ├── apprendys-prenom.service (base.nix, AVANT le display-manager)
  │     lit /home/apprendys/.config/apprendys/user-name puis /var/lib/apprendys/user-name
  │     → usermod -c (GECOS) → le menu Whisker & SDDM affichent le prénom
  │
  ├── SDDM ──► autologin user « apprendys » ──► XFCE
  │
  └── session XFCE (home-manager : home/apprendys.nix)
        icônes bureau, raccourcis, thème, et au 1er login :
        apprendys-session-init seed ~/.config/apprendys/ depuis /var/lib/apprendys/
```

Détail important sur **le prénom & le profil de style** :
- L'installateur écrit le prénom et le set d'icônes dans **`/var/lib/apprendys/`**
  (`user-name`, `profile`) — PAS dans le home. Raison : écrire dans le home avant le 1er boot
  ne survit pas à l'activation home-manager (les fichiers seraient écrasés).
- Au 1er login, `apprendys-session-init` recopie ces valeurs vers `~/.config/apprendys/`.
- Ensuite « Mon Apprendys » (l'app de réglages) écrit dans `~/.config/apprendys/user-name`,
  qui est prioritaire.

---

## 6. La mise à jour automatique (OTA) — `modules/ota-installed.nix`

C'est ce qui rend le parc maintenable à distance, sans toucher aux machines.

- Un **timer systemd hebdomadaire** (`apprendys-ota.timer`, `Persistent=true` → rattrape si
  le PC était éteint, `RandomizedDelaySec=2h`).
- Le service lance :
  ```
  nixos-rebuild switch --flake github:Ikkitsuna/apprendys-nix?ref=main#apprendys-installed --refresh
  ```
  → il va chercher la **branche `main` du repo GitHub public**, reconstruit le système, et
  bascule dessus de façon **atomique**. Régression ? L'ancienne génération est toujours au
  menu GRUB → rollback.
- **Garde-fou pile CMOS** : si l'année système < 2026 (pile morte → date fausse → SSL cassé),
  l'OTA **saute** (bug terrain V1). C'est `[ "$(date +%Y)" -ge 2026 ] || exit 0`.
- **Bouton « Vérifier maintenant »** dans Mon Apprendys (espace parent PIN) : autorisé via
  **polkit** (pas de sudo sur le système installé), et **uniquement** le `start` du service
  `apprendys-ota.service` par l'utilisateur `apprendys`.

**Donc : pour déployer une mise à jour à TOUT le parc, tu pousses sur `main`.** (Détails
opérationnels dans `OPERATIONS.md`.)

---

## 7. Le système de priorités NixOS (à comprendre pour ne rien casser)

Plusieurs modules définissent parfois la même option ; NixOS tranche par **priorité**
(nombre **plus petit = priorité plus haute**) :

| Helper | Priorité | Usage typique ici |
|---|---|---|
| `lib.mkOverride 40` | 40 | `release.nix` : écrase même un `mkForce` (durcir l'ISO prod) |
| `lib.mkForce` | 50 | `light.nix` : forcer SSH/sudo ON pour le debug |
| (valeur nue) | 100 | définition normale (`base.nix`) |
| `lib.mkDefault` | 1000 | base modifiable par un profil |

Exemple concret du **durcissement prod** : `light.nix` ouvre SSH (`mkForce true`, 50) et
sudo sans mot de passe ; `release.nix` (présent uniquement dans l'ISO installeur livrée)
repasse tout en `mkOverride 40` → SSH off, sudo password, clé debug retirée, `wheel` retiré.
C'est pour ça que l'ISO `…-sshtest` (sans `release.nix`) garde SSH ouvert et **ne doit jamais
être livrée**.

---

## 8. Les optimisations « clé USB » (pourquoi `base.nix` est si particulier)

Une clé USB meurt si on écrit dessus en continu. `base.nix` minimise les écritures NAND :

- **ZRAM** (swap compressé en RAM, zstd, 50 %) — un swapfile sur clé tuerait la NAND en jours.
- **`vm.swappiness = 0`** — interdit d'utiliser la clé comme swap.
- **journald en RAM** (`Storage=volatile`, 64 Mo) — pas de logs persistants sur flash.
  (Sur le système **installé**, `installed.nix` repasse `Storage=auto` 200 Mo : disque interne,
  logs utiles au SAV.)
- **`/tmp` en tmpfs**, flush des dirty pages espacé (60 s).

Ces réglages expliquent des choix qui paraîtraient bizarres sur un PC normal.

---

## 9. Où vit quoi — table de correspondance rapide

| Tu cherches… | Va voir |
|---|---|
| Ce qui se construit (ISO, configs) | `flake.nix` |
| Réglages système globaux, user `apprendys`, locale, fonts, ZRAM, prénom→GECOS | `modules/base.nix` |
| Applis installées (Firefox, LibreOffice, Xournal++…) | `modules/apps.nix` |
| Lis-moi / Le Perroquet / LireCouleur / Luciole / réglages DYS | `modules/accessibility.nix` + `packages/` |
| L'installateur 3-clics (partitionnement, `nixos-install`) | `modules/installer.nix` + `packages/apprendys-installer.nix` |
| Mise à jour OTA | `modules/ota-installed.nix` |
| Durcissement de l'ISO livrée | `modules/release.nix` |
| Bootloader, disques, firmware du PC installé | `profiles/installed.nix` |
| Quirks matériel (vieux PC) | `modules/hardware-quirks.nix` |
| Session XFCE (bureau, icônes, raccourcis, thème) | `home/apprendys.nix` |
| L'app de réglages « Mon Apprendys » | `packages/apprendys-app/` |
| VM de dev | `modules/dev-vm.nix` + `hardware/dev-vm.nix` |

→ Le détail fichier par fichier est dans **`MODULES.md`**. Le « comment je fais X » est dans
**`OPERATIONS.md`**.
