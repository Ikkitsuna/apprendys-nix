# Apprendys OS — Runbook opérationnel

> **But** : le « comment je fais X » concret. Build, test, flash, mise à jour du parc,
> rollback, debug. Suppose que tu as lu `ARCHITECTURE.md`.
> Repo public : `github.com/Ikkitsuna/apprendys-nix` (branche `main` = ce que reçoit l'OTA).

---

## 0. Prérequis

- Nix avec flakes activé (`experimental-features = nix-command flakes`).
- Le repo cloné. Toutes les commandes se lancent **à la racine du repo**.
- Pour flasher/tester : `dd`, `qemu`/`libvirt` (`virsh`), `ssh`, `xdotool` (pilotage GUI).

---

## 1. Construire les images

```bash
# LE produit (clé installateur 3-clics, offline)
nix build .#apprendys-installer-iso

# Clé live standard (sans installer)
nix build .#apprendys-light-iso

# Clé live PC récent
nix build .#apprendys-pro-iso

# Clé école (proxy + restrictions)
nix build .#apprendys-ecole-iso

# Image de TEST de l'installateur (SSH ouvert pour pilotage auto) — NE PAS LIVRER
nix build .#apprendys-installer-iso-sshtest
```

Le résultat est dans `result/iso/*.iso` (SquashFS demand-paged). Le premier build est long
(toute la closure). Les suivants réutilisent le cache Nix.

> **Vérifier ce que produit le flake** : `nix flake show`

---

## 2. Flasher une clé USB

```bash
# Repère le device (PAS une partition) — ex: /dev/sdX
lsblk

# Flash (⚠️ écrase tout le device ciblé)
sudo dd if=result/iso/nixos.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

Toujours **revérifier `of=`** avant d'appuyer : `dd` n'a pas de filet.

---

## 3. Tester sans flasher

### a) Tester le système installé (VM de dev, itération rapide)

`apprendys-dev` est une vraie VM NixOS qu'on **rebuild en place** (pas d'ISO). C'est le moyen
le plus rapide d'itérer sur un module.

```bash
# Depuis la VM de dev (ou via ssh), après avoir édité un module :
sudo nixos-rebuild switch --flake .#apprendys-dev
```

La VM de dev (`apprendys-dev`) tourne sur **Proxmox à `10.1.0.26`** (cf `modules/dev-vm.nix`),
SSH ouvert, user **`florent`** (sudo NOPASSWD, clé autorisée) ou `apprendys` :
`ssh florent@10.1.0.26`. (À ne pas confondre avec une VM libvirt locale jetable, qui sert
plutôt à tester les ISO — cf §3b.)

### b) Tester l'ISO installateur en VM (pilotage autonome)

On boote l'image `…-sshtest` dans une VM libvirt et on pilote l'installateur GUI à distance.
Workflow validé (cf. mémoire `apprendys-test-vm-workflow`) :

```bash
# 1. Créer/booter une VM libvirt sur l'ISO sshtest (disque vierge attaché = la cible d'install)
#    (virt-install / virsh define + start, OVMF pour tester l'UEFI, seabios pour le legacy)

# 2. SSH dans la live (light.nix ouvre SSH sur l'ISO de test)
ssh apprendys@<ip-vm>        # mot de passe : apprendys

# 3. Piloter l'installateur graphique via XTEST :
#    export DISPLAY=:0 ; puis xdotool pour cliquer les boîtes zenity
DISPLAY=:0 xdotool mousemove <x> <y> click 1
```

**Pièges connus (ne pas se faire avoir) :**
- Les **coordonnées xdotool** se mesurent sur des **captures natives** (pas redimensionnées),
  sinon on clique à côté.
- Passer par **XTEST** (`xdotool` réel), pas par des events synthétiques que zenity ignore.
- Les dialogues **zenity** : `--question` renvoie rc=1 sur Annuler (normal, pas une erreur).
- Capture d'écran de contrôle : `ffmpeg` PPM→PNG depuis le framebuffer de la VM.

### c) Vérifier que ça boote vraiment

Après une install en VM, retire l'ISO et reboote sur le disque : tu dois voir GRUB
(5 générations max) → autologin `apprendys` → XFCE avec le prénom dans le menu Whisker.

---

## 4. Déployer une mise à jour à TOUT le parc (OTA)

C'est le point le plus puissant — et le plus sensible. **Pousser sur `main` = mettre à jour
toutes les machines installées** (à leur prochain réveil du timer, ou via « Vérifier
maintenant » dans Mon Apprendys).

```bash
# 1. Éditer le(s) module(s) concerné(s).

# 2. TOUJOURS tester d'abord en VM de dev (§3a) — une régression poussée sur main
#    part chez tous les clients.

# 3. Vérifier que la cible OTA build SANS erreur :
nix build .#nixosConfigurations.apprendys-installed.config.system.build.toplevel

# 4. Commit + push sur main
git add -A
git commit -m "..."
git push origin main
```

Côté client, `apprendys-ota.service` fait :
`nixos-rebuild switch --flake github:Ikkitsuna/apprendys-nix?ref=main#apprendys-installed --refresh`
→ nouvelle génération atomique, rollback dispo au menu GRUB si pépin.

**Forcer la MAJ sur une machine précise** (au lieu d'attendre le timer) :
```bash
systemctl start apprendys-ota.service      # sur la machine, en tant qu'apprendys via polkit (bouton Mon Apprendys)
journalctl -u apprendys-ota.service -f     # suivre
```

> ⚠️ **Garde-fous à connaître** :
> - Si l'année système < 2026 (pile CMOS morte), l'OTA **se saute** volontairement.
> - Le rebuild a besoin de **réseau** (joindre github.com). Pas de réseau = pas de MAJ, on
>   réessaie au timer suivant (`Persistent=true`).
> - **Ne jamais casser le build de `apprendys-installed`** : une `main` qui ne compile pas
>   bloque l'OTA du parc entier. D'où l'étape 3 obligatoire.

---

## 5. Rollback

### Sur une machine (l'utilisateur ou toi)
- **Au boot** : menu GRUB → choisir la génération précédente (5 gardées).
- **En ligne de commande** (si tu as un accès) :
  ```bash
  sudo nixos-rebuild switch --rollback
  # ou choisir une génération précise :
  sudo /run/current-system/bin/switch-to-configuration switch   # après nix-env --rollback
  ```

### Côté repo (annuler une MAJ pour tout le parc)
```bash
git revert <commit-foireux>
git push origin main
```
Au prochain cycle OTA, les machines repassent sur la version saine.

---

## 6. Debug

- **Logs de l'installateur** (sur la live, pendant/après une install) : `/tmp/apprendys-install.log`.
  Le dialogue d'erreur zenity affiche toujours « Étape échouée : … » + ce chemin.
- **Logs système** : `journalctl -b` (boot courant), `journalctl -u <service>`.
  Rappel : sur la **clé/live**, journald est en RAM (volatile) → rien ne survit au reboot.
  Sur le **PC installé**, logs persistants (200 Mo).
- **Accès SSH** : disponible sur les ISO `light`/`pro`/`sshtest` (`apprendys` / `apprendys`),
  **fermé** sur l'ISO installeur livrée (`release.nix`). Pour debugger l'install livrée, builder
  la variante `…-sshtest`.
- **Inspecter le système installé sans le booter** :
  ```bash
  nix build .#nixosConfigurations.apprendys-installed.config.system.build.toplevel
  ls -l result/         # explorer la closure
  ```

---

## 7. Modifier le système — la boucle de travail type

```
1. Éditer le module/package concerné (voir MODULES.md pour savoir lequel).
2. Rebuild la VM de dev :   sudo nixos-rebuild switch --flake .#apprendys-dev
3. Tester le comportement dans la VM.
4. Si ça touche le PC installé : nix build .#nixosConfigurations.apprendys-installed...toplevel
5. Si ça touche l'ISO : nix build .#apprendys-installer-iso  (+ test VM §3b).
6. Commit + push (= OTA pour le parc) — APRÈS avoir testé.
```

DRY/YAGNI : une brique réutilisable → un **module** ; un réglage propre à une variante → le
**profil**. Ne mets jamais un secret/clé de prod dans le repo (il est **public**).

---

## 8. Checklist « avant de livrer une clé »

- [ ] Build avec `apprendys-installer-iso` (PAS la variante `-sshtest`).
- [ ] `release.nix` bien présent → SSH off, sudo password, clé debug retirée, pas de `wheel`.
- [ ] Test d'install complet en VM (UEFI **et** legacy BIOS) → boot OK, prénom OK.
- [ ] Vérifier les labels après install : partition root `APPRENDYS`, ESP `APPR-EFI`.
- [ ] Retirer la clé, rebooter sur le disque : autologin + XFCE + style choisi.

---

## 9. Points sensibles à ne jamais oublier

| Risque | Garde-fou |
|---|---|
| Pousser une régression à tout le parc | Tester en VM dev + `nix build …apprendys-installed` AVANT `push main` |
| Livrer une ISO avec SSH ouvert | Ne jamais livrer `…-sshtest` ; vérifier `release.nix` |
| L'installateur efface le mauvais disque | Il exclut déjà l'USB live (`TRAN=usb`), loop, sr, zram — ne pas toucher cette logique sans test |
| Labels de partition changés | `APPRENDYS` / `APPR-EFI` sont en dur dans `installed.nix` ET l'installateur — changer les deux ensemble |
| Repo public | Aucun secret/clé privée dans le repo |
