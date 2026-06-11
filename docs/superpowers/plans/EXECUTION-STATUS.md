# État d'exécution MVP — 2026-06-11

> Reprise : suivre ce fichier + le plan `2026-06-11-mvp-apprendys-installed.md`.
> Branche : `mvp-installed`. HEAD : `4432689`.

## CODE TERMINÉ — Tasks 1-9, 11, 12 (commits 91004e2 → 4432689)

| Task | Commit | Notes |
|---|---|---|
| 1 Baseline git | 91004e2 | branche mvp-installed |
| 2 Nix sur host Arch | — | nix 2.34.7, flakes OK |
| 3 Fix HM clobber | 43935a4 | force=true Bureau/*.desktop |
| 4 VM unifiée | d5a9dc7 | switch depuis le repo, 0 failed units. ⚠️ sudo VM = florent@ (plus apprendys@) |
| 5 Vosk wheel PyPI | acab0c7 | fetchurl (tag plateforme à point), importsCheck OK |
| 6 apprendys-stt | 578e0a2 + b8b0389 | verrou anti double-appui, PDEATHSIG arecord, gardes PID/JSON |
| 7 session-init | c8fb212 + 3790203 | migration inline→package (parité 9 blocs) ; bug icon-set symlink corrigé |
| 8 Profil installé | 0e6af9a | labels APPRENDYS/APPR-EFI, GRUB nodev+removable, SSH/sudo OFF, firmware WiFi |
| 9 Installateur | 40b29f9 → 745ce78 | **3 bugs critiques review+corrigés** : XAUTHORITY sudo, RCE eval lsblk, échappement Pango prénom |
| 11 OTA (code) | 2202d22 | timer weekly Persistent, garde CMOS, ordonnancement réseau. Review ✅ |
| 12 Durcissement (code) | 4432689 | release.nix : SSH off, clé debug retirée, wheel retiré, sudo gardé pour l'installateur. Review ✅ |

## En cours

- **Build ISO finale** (intègre OTA + durcissement) en arrière-plan : PID 11001, log `/tmp/apprendys-iso-final.log`. C'est CETTE ISO qu'on flashe pour le test/prod.

## VALIDATION NUIT 11→12 juin — mécanisme d'install + boot PROUVÉ (sans GUI)

Script `/tmp/apprendys-install-validate.sh` : reproduit do_install() sur image fichier
(loop device, garde-fou /dev/loop only), PUIS boot direct kernel en QEMU.

**Résultats — tout vert sauf artefacts host (pas des bugs Apprendys) :**
- ✅ Partitionnement GPT + labels APPR-EFI / APPRENDYS : parfait
- ✅ mkfs.fat / mkfs.ext4 : OK
- ✅ `nixos-install --system` OFFLINE : closure complète copiée (tts, stt, session-init,
  libreoffice, piper, sddm, toplevel) → système installable 100 % sans réseau, prouvé
- ✅ **BOOT jusqu'au bureau enfant** : kernel 6.18 → initrd (disque SATA via ahci/sd_mod) →
  systemd → SDDM autologin → XFCE → session-init pose les 3 icônes + fond nuages.
  Preuve : `docs/superpowers/plans/apprendys-installed-boot-proof.png`
- ✅ mount/util-linux présents dans le système installé (vérifié)

**Artefacts host (NON bugs — n'arrivent PAS sur la vraie ISO NixOS) :**
- L'install bootloader via `nixos-install`/`nixos-enter` depuis Arch échoue (PATH chroot,
  « mount: commande introuvable ») → contourné par boot direct kernel QEMU. Sur la vraie
  ISO l'environnement est complet, ça marche.
- QEMU de nixpkgs cassé sur ce host (SDL3 abort) → utiliser `/usr/bin/qemu-system-x86_64`.
- Ne JAMAIS mettre l'image scratch dans /tmp (tmpfs RAM 16G) ni sous /home/florent
  (perms 701, nix-daemon ne traverse pas) → utiliser /var/tmp (disque réel).

→ **Conclusion : le cœur de Task 10 est validé.** Le test GUI de Florent ne reste à faire
  que pour le câblage des 3 dialogues zenity (risque faible).

## RESTE À FAIRE — nécessite Florent (gates humaines)

1. **Task 10 — test bout-en-bout VM** (les 3 clics = Florent dans virt-viewer) :
   ```
   ISO=$(tail -1 /tmp/apprendys-iso-final.log)   # chemin /nix/store/...iso
   virt-install --connect qemu:///system --name apprendys-test-install \
     --memory 4096 --vcpus 2 --disk size=40 --os-variant generic \
     --cdrom "$ISO/iso/"*.iso --boot uefi --noautoconsole
   virt-viewer --connect qemu:///system apprendys-test-install &
   ```
   → double-clic « Installer Apprendys » → 3 clics → reboot sans ISO → checklist : TTS Ctrl+Espace, STT notif Ctrl+Maj+Espace, LireCouleur dans Writer, `cat ~/.config/apprendys/user-name`, SSH refusé. Puis refaire **sans `--boot uefi`** (SeaBIOS legacy).

2. **Task 11 — push GitHub** : ⚠️ **DÉCISION FLORENT public vs privé**. `gh` PAS installé sur le host (`nix profile install nixpkgs#gh` ou `git remote add` + token).
   ⚠️⚠️ **PIÈGE OTA À RÉGLER AVANT D'EXPÉDIER** : `modules/ota-installed.nix` pointe sur `github:Ikkitsuna/apprendys-nix#apprendys-installed` SANS `?ref=`. Sans ref → branche par défaut du repo. Le code est sur `mvp-installed`. Donc soit : (a) merger `mvp-installed` → branche par défaut au push, soit (b) épingler `?ref=mvp-installed` dans l'URL OTA. Sinon l'OTA no-op silencieusement (le `|| echo` avale l'échec). À trancher au moment du push.

3. **Task 12 — finalisation** : après test GUI OK → tag `mvp-iso-v1` ; puis checklist matériel réel (flash clé + Blackview BIOS 2015 + 1 PC UEFI + micro réel pour Vosk).

## Rappels d'environnement
- nix host : `export PATH="/nix/var/nix/profiles/default/bin:$PATH"`
- VM dev : ssh apprendys@192.168.122.99 (tests) / **florent@ pour sudo -n** (rebuild)
- Build ISO : `nix build .#apprendys-installer-iso -L` (~15-25 min)
- ⚠️ guetteurs : NE PAS filtrer `pgrep` sur une chaîne que la commande de surveillance contient (auto-match → boucle infinie). Surveiller un PID précis (`kill -0 $PID`).

## Rappels d'environnement

- nix host : `export PATH="/nix/var/nix/profiles/default/bin:$PATH"`
- VM dev : ssh apprendys@192.168.122.99 (tests) / **florent@ pour sudo -n** (rebuild)
- Build ISO : `nix build .#apprendys-installer-iso -L` (~15-25 min)
- sudo host : NOPASSWD OK, snapshots Timeshift dispo
