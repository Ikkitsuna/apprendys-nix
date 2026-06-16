# État d'exécution MVP — 2026-06-16 (reprise après 4 jours)

> Reprise : suivre ce fichier + le plan `2026-06-11-mvp-apprendys-installed.md`.
> Branche : `mvp-installed`. Décision Florent : repo **PUBLIC** (OTA simple).

## SESSION 16 JUIN — 3 bugs « Mon Apprendys » trouvés par Florent (captures 12/06) + corrigés
Cap dossier `~/Images/Copies d'écran/` (12 juin). Root-cause + fix (commit après f2e6641) :
1. **FREEZE sur Appliquer (critique)** : `subprocess.run(xfce4-panel --restart, capture_output=True)` SANS timeout → le panel relancé hérite du tuyau stdout, ne le ferme jamais → gel infini sur le thread GTK. + session-init (qui backgroundise un restart panel) capturé → gel 60 s. Fix : helpers `_spawn`/`_run` en DEVNULL, suppression du restart redondant, apply dans un thread.
2. **Prénom absent du menu Whisker** : `set_whisker_title` écrivait `button-title` (label bouton, caché) au lieu du GECOS que Whisker affiche. Fix : `apprendys-prenom.service` lit aussi `~/.config/apprendys/user-name`, déclenchable à chaud par l'app via règle polkit (base.nix).
3. **Mot de passe à la MAJ** : bouton lance `apprendys-ota.service`, règle polkit installée seulement (pas sur ISO live). Fix : bouton masqué si service absent (`ota_available()`).

**À VÉRIFIER en VM** (ISO sshtest en build, `/var/tmp/apprendys-sshtest-iso4`) :
- Live : style sans freeze, prénom→Whisker, bouton MAJ masqué.
- Installé (vraie install) : bouton MAJ présent + marche sans mot de passe (= valide aussi la règle polkit OTA, jamais testée sur installé).

## TÂCHE EN COURS : GitHub + OTA (Task 11) — EN PAUSE le temps des fixes
- Décision : repo **PUBLIC**. `gh` installé mais PAS loggué → Florent doit `gh auth login`.
- Avant push : nettoyer le `hashedPassword` de `modules/dev-vm.nix` (hash brute-forçable en public, VM dev only).
- Fix ref OTA : pousser le code sur la branche par défaut (renommer `mvp-installed`→`main` ou pin `?ref=`) sinon l'OTA no-op.
- Pas de clé privée dans l'historique (vérifié). Clé SSH *publique* florent@ArchWork = sans danger.

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

## Session 12 juin (après 1er test VM de Florent) — bugs + thèmes + trous V1

Florent a testé l'ISO sur VM réelle : boot OK, Vosk/Piper OK. A signalé des bugs + voulu cibler tous les âges. Traité :

| Commit | Quoi |
|---|---|
| `7b557e8` | **Bug install bloquant** : wipefs EBUSY (automount disque cible) → démontage forcé + swapoff avant wipefs. + label « Prénom » neutre (profil Adulte demandait prénom d'enfant) |
| `e398394` | **Profil = thème complet** : junior=enfant (Greybird clair, nuages, 72px, Luciole 13) ; adult/teen=adulte (Greybird-dark, Papirus-Dark, slate, 48px, Luciole 11). session-init applique l'ambiance selon `icon-set` |
| `bb2c51e` | **Sécurité du travail** : autosave LibreOffice + Xournal → ~/Devoirs/autosave (seed-si-absent), dossiers Devoirs créés, bookmark GTK « Mes Devoirs ». + **timezone Indian/Reunion** |
| `a5c3859` | **Préchargement Vosk** au login (fini le cold start ~2 min) |
| `56dcb31` | **Profil+prénom via /var/lib/apprendys** (l'installateur écrit là, session-init seed le home au 1er login — robuste vs home-manager) |
| `e103000` | Preuves de boot : `apprendys-installed-boot-proof.png` (enfant) + `apprendys-adulte-boot-proof.png` (adulte slate) |

**Validé en image (install→boot direct kernel QEMU)** : profil adulte → Greybird-dark + Papirus-Dark + 48px + slate, vérifié dans le xfconf réel ET à l'écran.

**Analyse V1/V2 (ZERO-TO-HERO lu)** : gnuramage/P4/P5/persistence = parqués pour le Produit 2 nomade (modules dans le repo, non câblés). Trous restants : onboarding (zappé pour MVP), **app réglages parent** (gros, post-MVP — d'autant plus utile maintenant que profil=thème). Accès Devoirs depuis ailleurs → futur argument **Apprendys+ cloud** (au lieu de partition NTFS).

**Nuance honnête** : le « bug profil effacé au boot » n'a jamais été prouvé (le test ne seedait pas, à cause de l'échec bootloader host + set -e). Fix /var/lib gardé car meilleure archi.

## Session 12 juin (après-midi) — test GUI AUTONOME en VM (ssh+xdotool) : 2 VRAIS bugs trouvés+fixés

Test de l'installateur réel piloté à distance (VM `apprendys-sshtest`, ISO sshtest, screenshots virsh) :

| Commit | Bug trouvé en conditions réelles |
|---|---|
| `0bd97bd` | **LE vrai « wipefs error »** : le log /tmp était créé en phase user PUIS root ne pouvait plus y écrire (`fs.protected_regular` NixOS) → le 1er `>>$LOG` échouait → étape wipefs déclarée morte alors que wipefs ne tournait même pas. C'était probablement ça le bug du 1er test de Florent (l'automount EBUSY était plausible mais jamais confirmé). Fix : log créé en phase root + `rm -f` préalable |
| `2699be8` | **Course udev au montage** : `mount` sans `-t` juste après mkfs.ext4 → libblkid vue périmée → sondes FAT/ISOFS en dmesg → « superbloc erroné ». Le même mount marche 30 s après. Fix : `udevadm settle` + `-t ext4/vfat` explicite + 3 retries |

Les 4 dialogues zenity validés visuellement en VM (warning → disque radiolist → prénom+profil combo Adulte → récapitulatif). Screenshots : `/var/tmp/apprendys-gui-test/`.
⚠️ Les anciennes ISO (dont `ISO-INSTALLEUR-MVP.iso` du 11 juin) ont CES bugs → **rebuild obligatoire avant flash** (`nix build .#apprendys-installer-iso`).

## Session 12 juin (fin d'aprèm) — Task 13 : « Mon Apprendys » porté + styles par look

Commits `1d4ae92` (prénom GECOS + teen pour Adulte) puis `be64e00` + `0a4...` :
- **App V1 portée** (packages/apprendys-app[.nix]) : cartes de style, police Luciole/OpenDyslexic + tailles, curseur, espace parent PIN (changelog, bouton OTA via polkit, vitesse TTS réelle via piper --length_scale), guides V1 embarqués (12 Mo).
- **Styles nommés par LOOK, pas par âge** (décision Florent) : Mignon (junior) / Classique (teen) / Monochrome (adult, icônes inversées en blanc). Installateur : combo 3 styles.
- Changement de style via l'app → session-init relancé → ambiance complète suit.
- font-style/font-size de l'app PRIMENT sur l'ambiance au login (session-init).
- **Validé en VM live (apprendys-sshtest3)** : app lancée, Monochrome appliqué en direct (fond+thème+icônes blanches+panel), retour Classique OK. Screenshots /var/tmp/apprendys-gui-test/6x-*.png.
- ⚠️ **BUG CONFIRMÉ (mineur, diagnostiqué à 90 %)** : après « Appliquer », le dialogue « Changements appliqués ! » s'affiche en **10x10 px** à (10,10) → invisible → l'app semble ne jamais se fermer (elle attend l'OK). Cause probable : la MessageDialog est mappée pendant le pkill/restart de xfdesktop dans apply_profile. **Fix suggéré** : dans `_on_apply_all`, montrer le dialogue AVANT apply_profile, ou différer apply_profile via GLib.idle_add après d.destroy(), ou simplement supprimer le dialogue (l'effet est visible à l'écran, l'app peut quitter directement). Fichier : packages/apprendys-app/apprendys-app.py, `_on_apply_all` + `apply_profile`.

## ISO finale prête à flasher (⚠️ PÉRIMÉE — re-builder avec les fixes 0bd97bd+2699be8 + Task 13)

`apprendys-nix/ISO-INSTALLEUR-MVP.iso` (4,0 Go) → `/nix/store/y3944yld...iso`. Inclut les 6 commits ci-dessus. C'est CETTE ISO pour le test GUI + prod.
`sudo dd if=ISO-INSTALLEUR-MVP.iso of=/dev/sdX bs=4M status=progress oflag=sync`

## Rappel artefact host (pour mes tests, PAS un bug produit)
`nixos-install` depuis Arch échoue à l'étape bootloader (`mount: commande introuvable` dans le chroot) → contourné par boot direct kernel QEMU. Sur la vraie ISO NixOS, l'install bootloader marche.

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
