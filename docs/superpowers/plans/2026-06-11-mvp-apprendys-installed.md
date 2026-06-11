# MVP « apprendys-installed » — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produire l'ISO installeur Apprendys : on boote un vieux PC dessus, 3 clics (avertissement → prénom+profil → confirmation), ~20 min, et l'enfant a un NixOS Apprendys installé en dur avec TTS/STT/LireCouleur et MAJ OTA.

**Architecture:** Le flake `apprendys-nix` existant (Phase 1 : ISO live validée) gagne une `nixosConfiguration` `apprendys-installed` (montage par labels disque, GRUB UEFI+legacy) dont la closure complète est embarquée dans l'ISO (`system.extraDependencies`) pour un `nixos-install --system` 100 % offline. L'installateur est un script zenity (pas de disko : `sgdisk` + `mkfs` avec labels). L'OTA installée est un timer systemd `nixos-rebuild switch --flake github:…` avec rollback natif par générations.

**Tech Stack:** Nix flakes, nixos-generators (format iso), home-manager, zenity, sgdisk, Vosk (wheel PyPI), Piper TTS, GTK3.

**Contexte machines :**
- Host (Arch, 16 cœurs) : repo `/home/florent/Documents/NixProj/apprendys-nix/`, **pas de nix installé** (Tâche 2).
- VM dev : libvirt `apprendys-v2-dev`, `ssh apprendys@192.168.122.99` (clé OK, sudo NOPASSWD), NixOS 26.05, nix 2.34.6.
- Spec : `/home/florent/Documents/NixProj/Apprendys/vkey/MASTERPLAN-V3.md` §3.
- Scripts V1 de référence : `/tmp/apprendys-clone/patches/usr/local/bin/` (re-cloner `https://github.com/Ikkitsuna/apprendys` si absent).

**Hors périmètre MVP (ne pas implémenter) :** persistance clé physique (P4/P5), gnuramage, OTA 2-couches clé, profils light/pro/école en prod, app Windows, onboarding visuel, Ma Bulle, cards QR.

---

### Task 1: Baseline git du repo

Le repo n'a **aucun commit** (tout est en staging depuis des semaines). Avant toute modif : un commit de référence.

**Files:**
- Aucun nouveau — commit de l'existant.

- [ ] **Step 1: Vérifier l'état**

Run: `cd /home/florent/Documents/NixProj/apprendys-nix && git status --short | head -20 && git log --oneline | head -3`
Expected: une liste de fichiers `A ` (staged), et `fatal: votre branche actuelle 'master' ne contient encore aucun commit`.

- [ ] **Step 2: Commit initial**

```bash
cd /home/florent/Documents/NixProj/apprendys-nix
git add -A
git commit -m "Phase 1 : flake ISO live validée (bureau XFCE, TTS Piper, fonts DYS)"
```

- [ ] **Step 3: Vérifier**

Run: `git log --oneline`
Expected: 1 commit.

---

### Task 2: Machine de build — installer Nix sur le host Arch

L'ISO se build en ~10-20 min sur 16 cœurs vs ~1h+ sur la VM 8 Go. Installation multi-user officielle.

**Files:** aucun (système host).

- [ ] **Step 1: Installer Nix (daemon multi-user)**

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```
(Répondre oui aux prompts. Alternative Arch : `sudo pacman -S nix && sudo systemctl enable --now nix-daemon` puis `sudo usermod -aG nix-users florent`.)

- [ ] **Step 2: Activer les flakes**

```bash
sudo mkdir -p /etc/nix
echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon 2>/dev/null || true
```

- [ ] **Step 3: Vérifier (nouveau shell pour le PATH)**

Run: `nix --version && nix run nixpkgs#hello`
Expected: version ≥ 2.18 puis `Hello, world!`.

- [ ] **Step 4: Build de contrôle — l'ISO Phase 1 doit encore builder**

Run: `cd /home/florent/Documents/NixProj/apprendys-nix && nix build .#apprendys-light-iso -L`
Expected: succès, `result/iso/*.iso` présent (~3 Go). Premier build long (téléchargement). Si échec : ne PAS corriger à l'aveugle — noter l'erreur, c'est la baseline.

---

### Task 3: Fix home-manager « would be clobbered »

`home-manager-apprendys.service` échoue sur la VM : les fichiers `Bureau/*.desktop` et `panel/launcher-1{5,6,7}/*.desktop` existent déjà (créés impérativement avant). Home-manager exige `force = true` pour les écraser.

**Files:**
- Modify: `home/apprendys.nix` (entrées `home.file."Bureau/*.desktop"` ~lignes 34-80, et toute autre déclaration des fichiers listés par l'erreur)

- [ ] **Step 1: Lister les fichiers en conflit (source de vérité = le log)**

Run: `ssh apprendys@192.168.122.99 'journalctl -u home-manager-apprendys.service --no-pager | grep "Existing file" | sed "s/.*Existing file .//;s/. would be clobbered//" | sort -u'`
Expected: liste de chemins (`/home/apprendys/Bureau/mes-devoirs.desktop`, etc.).

- [ ] **Step 2: Ajouter `force = true` à chaque déclaration correspondante**

Pour chaque chemin du Step 1, trouver sa déclaration dans `home/apprendys.nix` (`grep -n "mes-devoirs.desktop" home/apprendys.nix`) et ajouter l'attribut. Exemple (répéter pour `mes-devoirs`, `je-recherche`, `mes-lecons`, et les launchers panel s'ils sont déclarés en `home.file`/`xdg.configFile`) :

```nix
home.file."Bureau/mes-devoirs.desktop" = {
  force = true;   # fichier pré-existant sur les systèmes migrés — HM doit écraser
  text = ''
    [Desktop Entry]
    ...inchangé...
  '';
};
```

NB : si un chemin du Step 1 est écrit par le script `home.activation` (cat >) et **pas** déclaré en `home.file`, ne rien faire pour lui — il n'est pas la cause du clobber.

- [ ] **Step 3: Vérifier la syntaxe Nix**

Run: `nix eval .#nixosConfigurations.apprendys-dev.config.system.build.toplevel.drvPath --raw | head -c 80`
Expected: un chemin `.drv` (l'éval passe).

- [ ] **Step 4: Commit**

```bash
git add home/apprendys.nix
git commit -m "fix(hm): force=true sur les .desktop pré-existants (clobber au switch)"
```

---

### Task 4: Unification VM — la VM dev rebuilde depuis le repo

La VM tourne sur un flake séparé dans `/etc/nixos` (user `florent`, divergent). On la fait pointer sur LE repo : `hardware/dev-vm.nix` doit refléter le hardware réel de la VM locale (elle vient de Proxmox, UUIDs différents).

**Files:**
- Modify: `hardware/dev-vm.nix` (remplacé par le hardware-configuration réel de la VM)

- [ ] **Step 1: Récupérer le hardware réel de la VM**

```bash
cd /home/florent/Documents/NixProj/apprendys-nix
ssh apprendys@192.168.122.99 'cat /etc/nixos/hardware-configuration.nix' > /tmp/vm-hw.nix
diff /tmp/vm-hw.nix hardware/dev-vm.nix || true
```
Expected: un diff (UUIDs/options different probablement).

- [ ] **Step 2: Remplacer et vérifier le contenu**

```bash
cp /tmp/vm-hw.nix hardware/dev-vm.nix
grep -E "fileSystems|boot.initrd|device" hardware/dev-vm.nix
```
Expected: `fileSystems."/"` avec un UUID, modules initrd virtio.

- [ ] **Step 3: Synchroniser le repo vers la VM**

```bash
rsync -az --delete --exclude .git --exclude result /home/florent/Documents/NixProj/apprendys-nix/ apprendys@192.168.122.99:~/apprendys-nix/
```

- [ ] **Step 4: Rebuild de la VM depuis le repo**

Run: `ssh apprendys@192.168.122.99 'sudo nixos-rebuild switch --flake ~/apprendys-nix#apprendys-dev'`
Expected: `building the system configuration...` puis activation sans erreur. ⚠️ Si l'utilisateur `florent` disparaît de la VM c'est NORMAL (le repo déclare `apprendys` seul).

- [ ] **Step 5: Vérifier — plus aucune unit en échec**

Run: `ssh apprendys@192.168.122.99 'systemctl --failed --no-pager'`
Expected: `0 loaded units listed.` (le fix Task 3 règle home-manager-apprendys).

- [ ] **Step 6: Commit**

```bash
git add hardware/dev-vm.nix
git commit -m "feat(vm): hardware réel VM libvirt locale — VM unifiée sur le repo"
```

---

### Task 5: Packager Vosk (absent de nixpkgs)

Wheel PyPI manylinux avec `libvosk.so` embarquée → `autoPatchelfHook`.

**Files:**
- Create: `packages/vosk.nix`

- [ ] **Step 1: Confirmer le nom exact du wheel sur PyPI**

Run: `curl -s https://pypi.org/pypi/vosk/json | grep -o '"filename": "vosk-[^"]*x86_64[^"]*"' | head -3`
Expected: un nom type `vosk-0.3.45-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.whl`. **Adapter `version`/`platform` du Step 2 à ce résultat exact.**

- [ ] **Step 2: Écrire `packages/vosk.nix`**

```nix
{ lib, python3Packages, fetchPypi, autoPatchelfHook, stdenv }:

# Vosk STT — absent de nixpkgs (juin 2026). Wheel PyPI avec libvosk.so embarquée.
python3Packages.buildPythonPackage rec {
  pname = "vosk";
  version = "0.3.45";                # ← aligner sur le Step 1
  format = "wheel";

  src = fetchPypi {
    inherit pname version format;
    dist = "py3";
    python = "py3";
    abi = "none";
    platform = "manylinux_2_12_x86_64.manylinux2010_x86_64";  # ← aligner sur le Step 1
    hash = lib.fakeHash;             # ← remplacé au Step 3
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  propagatedBuildInputs = with python3Packages; [ cffi requests srt tqdm websockets ];

  pythonImportsCheck = [ "vosk" ];

  meta = with lib; {
    description = "Reconnaissance vocale offline (Kaldi) — moteur dictée Apprendys";
    homepage = "https://alphacephei.com/vosk/";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}
```

- [ ] **Step 3: Build → récupérer le vrai hash**

Run: `nix build --impure --expr 'with import <nixpkgs> {}; callPackage /home/florent/Documents/NixProj/apprendys-nix/packages/vosk.nix {}' -L 2>&1 | grep -A2 "hash mismatch"`
Expected: `got: sha256-…`. Remplacer `lib.fakeHash` par cette valeur.

- [ ] **Step 4: Re-build → succès + import OK**

Run: même commande sans le grep.
Expected: build OK (le `pythonImportsCheck` a déjà validé `import vosk`).

- [ ] **Step 5: Commit**

```bash
git add packages/vosk.nix
git commit -m "feat(pkg): vosk 0.3.45 depuis wheel PyPI (autoPatchelf, importsCheck)"
```

---

### Task 6: Le Perroquet — apprendys-stt (port V1) + câblage apps.nix

Port fidèle de `/tmp/apprendys-clone/patches/usr/local/bin/apprendys-stt.sh` : toggle PID, arecord → Vosk → xdotool. Chemins modèle : P4 (premium, plus tard) puis Nix store.

**Files:**
- Create: `packages/apprendys-stt.nix`
- Modify: `modules/apps.nix` (let-binding + systemPackages + pathsToLink + extraDependencies)
- Modify: `modules/accessibility.nix` (retirer le TODO vosk, pyaudio inutile)

- [ ] **Step 1: Écrire `packages/apprendys-stt.nix`**

```nix
{ lib
, writeShellApplication
, python3
, vosk                     # packages/vosk.nix, injecté par apps.nix
, vosk-model-fr-small      # packages/vosk-model-fr-small.nix, injecté par apps.nix
, alsa-utils               # arecord
, xdotool
, libnotify
, coreutils
, procps
}:

# Apprendys STT — Le Perroquet (dictée vocale offline)
# Port NixOS de V1 patches/usr/local/bin/apprendys-stt.sh
# Ctrl+Maj+Espace : toggle dictée — parle, le texte est tapé au curseur.
#
# Modèle : 1. /mnt/apprendys/models/stt (P4/premium, sans .bin = Vosk)
#          2. Nix store (baked) — vosk-model-fr-small

let pythonVosk = python3.withPackages (ps: [ vosk ]);
in writeShellApplication {
  name = "apprendys-stt";
  runtimeInputs = [ pythonVosk alsa-utils xdotool libnotify coreutils procps ];
  text = ''
    set +e   # tolérance pannes — jamais crasher devant l'enfant

    PIDFILE="/tmp/apprendys-stt.pid"
    P4_STT="/mnt/apprendys/models/stt"
    NIX_MODEL="${vosk-model-fr-small}/share/vosk-models/fr-small"

    if [ -d "$P4_STT" ] && [ -n "$(ls -A "$P4_STT" 2>/dev/null)" ] && ! ls "$P4_STT"/*.bin >/dev/null 2>&1; then
      VOSK_MODEL="$P4_STT"
    elif [ -d "$NIX_MODEL" ]; then
      VOSK_MODEL="$NIX_MODEL"
    else
      notify-send -i dialog-error "Erreur Dictée" "Modèle vocal non trouvé." -t 3000
      exit 1
    fi

    # Toggle : déjà en cours → on arrête
    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        rm -f "$PIDFILE"
        notify-send -i audio-input-microphone "Dictée terminée" "Le micro est éteint." -t 2000
        exit 0
      fi
      rm -f "$PIDFILE"
    fi

    notify-send -i audio-input-microphone "Dictée activée !" "Parle, j'écris pour toi.
Appuie encore pour arrêter." -t 3000

    python3 -u << ENDPY &
    import json, subprocess, sys, os, signal
    from vosk import Model, KaldiRecognizer

    model = Model("''${VOSK_MODEL}")
    rec = KaldiRecognizer(model, 16000)
    proc = subprocess.Popen(
        ["arecord", "-f", "S16_LE", "-r", "16000", "-c", "1", "-t", "raw", "-q"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    def cleanup(sig, frame):
        proc.terminate()
        sys.exit(0)
    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    while True:
        data = proc.stdout.read(4000)
        if len(data) == 0:
            break
        if rec.AcceptWaveform(data):
            text = json.loads(rec.Result()).get("text", "").strip()
            if text:
                subprocess.run(["xdotool", "type", "--delay", "20", text + " "],
                               env={**os.environ, "DISPLAY": ":0"})
    ENDPY

    STT_PID=$!
    echo "$STT_PID" > "$PIDFILE"
    wait "$STT_PID" 2>/dev/null
    rm -f "$PIDFILE"
  '';
}
```

⚠️ Heredoc : `''${VOSK_MODEL}` (échappé Nix → bash expanse), le reste du Python ne contient aucun `$`. Si shellcheck (intégré à `writeShellApplication`) bloque sur le heredoc, ajouter `# shellcheck disable=SC2154` au-dessus.

- [ ] **Step 2: Câbler dans `modules/apps.nix`**

Dans le `let` existant, ajouter :

```nix
  vosk = pkgs.callPackage ../packages/vosk.nix {};
  vosk-model-fr-small = pkgs.callPackage ../packages/vosk-model-fr-small.nix {};
  apprendys-stt = pkgs.callPackage ../packages/apprendys-stt.nix {
    inherit vosk vosk-model-fr-small;
  };
```

Dans `system.extraDependencies`, ajouter `vosk-model-fr-small`. Dans `environment.pathsToLink`, ajouter `"/share/vosk-models"`. Dans `environment.systemPackages`, remplacer la ligne commentée `# apprendys-stt` par `apprendys-stt` et ajouter `vosk-model-fr-small`.

- [ ] **Step 3: Nettoyer `modules/accessibility.nix`**

Supprimer `python3Packages.pyaudio` et le commentaire TODO vosk (le STT est livré par apps.nix) :

```nix
  environment.systemPackages = with pkgs; [
    piper-tts
    python3
    xsetroot
  ];
```

- [ ] **Step 4: Build + test sur la VM**

```bash
nix build .#nixosConfigurations.apprendys-dev.config.system.build.toplevel -L
rsync -az --delete --exclude .git --exclude result ./ apprendys@192.168.122.99:~/apprendys-nix/
ssh apprendys@192.168.122.99 'sudo nixos-rebuild switch --flake ~/apprendys-nix#apprendys-dev && apprendys-stt; sleep 2; apprendys-stt'
```
Expected: build OK ; sur la VM, 1er appel → pas d'erreur « Modèle vocal non trouvé » (le modèle charge ; `arecord` peut échouer sans micro virtuel — acceptable), 2e appel → toggle off propre. Critère minimal : exit code 0 et le PIDFILE se crée/s'efface.

- [ ] **Step 5: Commit**

```bash
git add packages/apprendys-stt.nix modules/apps.nix modules/accessibility.nix
git commit -m "feat: apprendys-stt (Le Perroquet) — port V1 sur Vosk nixifié"
```

---

### Task 7: session-init — LireCouleur, icon-set, nettoyage locks

Service de session (autostart XFCE) qui : active le set d'icônes (junior/teen/adult), installe LireCouleur côté user (unopkg, une fois), nettoie les locks Firefox/Chromium. Port du sous-ensemble V1 pertinent pour un PC installé.

**Files:**
- Create: `packages/apprendys-session-init.nix`
- Modify: `modules/apps.nix` (let + systemPackages)
- Modify: `home/apprendys.nix` (entrée autostart)

- [ ] **Step 1: Vérifier qu'aucun session-init n'existe déjà**

Run: `grep -rn "session-init" /home/florent/Documents/NixProj/apprendys-nix/ --include="*.nix" -l`
Expected: au plus des commentaires dans `home/apprendys.nix`. Si un module existe déjà : adapter au lieu de créer.

- [ ] **Step 2: Écrire `packages/apprendys-session-init.nix`**

```nix
{ lib
, writeShellApplication
, lirecouleur     # injecté par apps.nix
, libreoffice-fresh
, coreutils
, findutils
}:

# Apprendys session-init — lancé à chaque ouverture de session XFCE (autostart).
# 1. Active le set d'icônes selon ~/.config/apprendys/icon-set (défaut: junior)
# 2. Installe LireCouleur côté user (unopkg, une seule fois)
# 3. Nettoie les locks stale (port V1 : parentlock Firefox, SingletonLock Chromium)

writeShellApplication {
  name = "apprendys-session-init";
  runtimeInputs = [ libreoffice-fresh coreutils findutils ];
  text = ''
    set +e

    CONFIG_DIR="$HOME/.config/apprendys"
    ICON_BASE="$HOME/.local/share/icons/apprendys"
    mkdir -p "$CONFIG_DIR"

    # ── 1. Set d'icônes actif (junior | teen | adult) ──
    SET="junior"
    [ -f "$CONFIG_DIR/icon-set" ] && SET=$(cat "$CONFIG_DIR/icon-set")
    [ -d "$ICON_BASE/$SET" ] || SET="junior"
    if [ -d "$ICON_BASE/$SET" ]; then
      cp -f "$ICON_BASE/$SET"/*.png "$ICON_BASE/" 2>/dev/null
    fi

    # ── 2. LireCouleur (une fois par user) ──
    if [ ! -f "$CONFIG_DIR/lirecouleur_installed" ]; then
      if unopkg add "${lirecouleur}/share/lirecouleur/lirecouleur.oxt" 2>/dev/null; then
        touch "$CONFIG_DIR/lirecouleur_installed"
      fi
    fi

    # ── 3. Locks stale (V1 terrain : crash/coupure → app refuse de démarrer) ──
    find "$HOME/.mozilla" -name ".parentlock" -delete 2>/dev/null
    rm -f "$HOME/.config/chromium/SingletonLock" \
          "$HOME/.config/chromium/SingletonSocket" \
          "$HOME/.config/chromium/SingletonCookie" 2>/dev/null

    exit 0
  '';
}
```

- [ ] **Step 3: Câbler dans `modules/apps.nix`**

Dans le `let` : `apprendys-session-init = pkgs.callPackage ../packages/apprendys-session-init.nix { inherit lirecouleur; libreoffice-fresh = pkgs.libreoffice-fresh; };`
Dans `systemPackages` : ajouter `apprendys-session-init`.

- [ ] **Step 4: Autostart dans `home/apprendys.nix`**

```nix
  home.file.".config/autostart/apprendys-session-init.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Apprendys Session Init
      Exec=apprendys-session-init
      X-GNOME-Autostart-enabled=true
      NoDisplay=true
    '';
  };
```

- [ ] **Step 5: Test sur la VM**

```bash
nix build .#nixosConfigurations.apprendys-dev.config.system.build.toplevel -L
rsync -az --delete --exclude .git --exclude result ./ apprendys@192.168.122.99:~/apprendys-nix/
ssh apprendys@192.168.122.99 'sudo nixos-rebuild switch --flake ~/apprendys-nix#apprendys-dev && apprendys-session-init && ls ~/.config/apprendys/ && ls ~/.local/share/icons/apprendys/*.png | head -3'
```
Expected: `lirecouleur_installed` présent (ou absent si LO ne tourne pas headless — relancer une fois la session graphique ouverte), PNG junior copiés à la racine du dossier d'icônes.

- [ ] **Step 6: Vérif LireCouleur dans LibreOffice (via la console graphique virt-manager)**

Ouvrir la session XFCE de la VM → LibreOffice Writer → menu Outils : la barre/menu LireCouleur est présente.
Expected: extension visible. Sinon : `unopkg list` en terminal pour diagnostiquer.

- [ ] **Step 7: Commit**

```bash
git add packages/apprendys-session-init.nix modules/apps.nix home/apprendys.nix
git commit -m "feat: session-init (icon-set junior/adult, LireCouleur unopkg, locks V1)"
```

---

### Task 8: Profil installé + quirks matériel vieux PC

La `nixosConfiguration` cible : montage par **labels** (l'installateur crée les labels, aucun UUID à injecter), GRUB UEFI (`efiInstallAsRemovable`, les vieux BIOS UEFI ont des NVRAM capricieuses) + legacy (géré par l'installateur en Task 9), logs persistants (on est sur disque interne), rebind touchpad I2C (bug terrain V1 validé Blackview).

**Files:**
- Create: `profiles/installed.nix`
- Create: `modules/hardware-quirks.nix`
- Modify: `flake.nix` (nouvelle nixosConfiguration)

- [ ] **Step 1: Écrire `modules/hardware-quirks.nix`**

```nix
{ config, pkgs, lib, ... }: {
  # Touchpad I2C mort après warm boot (ALPS/Elan, vieux portables) — bug terrain V1.
  # Fix validé Blackview : unbind / sleep 0.3 / bind.
  systemd.services.apprendys-touchpad-rebind = {
    description = "Apprendys — rebind touchpad I2C (vieux PC)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for dev in /sys/bus/i2c/drivers/i2c_hid_acpi/i2c-*; do
        [ -e "$dev" ] || continue
        name=$(basename "$dev")
        echo "$name" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind 2>/dev/null || true
        sleep 0.3
        echo "$name" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind 2>/dev/null || true
      done
    '';
  };
}
```

- [ ] **Step 2: Écrire `profiles/installed.nix`**

```nix
{ config, pkgs, lib, ... }: {
  # Apprendys installé sur PC dédié (le « vieux PC du placard »)
  imports = [ ../modules/hardware-quirks.nix ];

  networking.hostName = "apprendys";

  # L'installateur (apprendys-installer) crée ces labels — montage générique,
  # aucun UUID machine-spécifique.
  fileSystems."/" = { device = "/dev/disk/by-label/APPRENDYS"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/APPR-EFI"; fsType = "vfat"; };

  boot.loader.grub = {
    enable = true;
    device = "nodev";              # legacy BIOS : grub-install manuel par l'installateur
    efiSupport = true;
    efiInstallAsRemovable = true;  # pas d'écriture NVRAM (vieux UEFI fragiles)
  };
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.grub.configurationLimit = 5;   # rollback OTA : 5 générations au menu

  # Disque interne : logs persistants utiles au SAV (base.nix les met en RAM pour la clé)
  services.journald.extraConfig = lib.mkForce ''
    Storage=auto
    SystemMaxUse=200M
  '';

  environment.variables.APPRENDYS_PROFILE = "installed";

  # Prod : SSH off, sudo off (défauts base.nix — ne PAS importer light.nix qui les force)
}
```

- [ ] **Step 3: Ajouter la configuration au `flake.nix`**

Sous `nixosConfigurations.apprendys-dev`, ajouter :

```nix
    # Système installé sur PC dédié — cible de l'installateur 3-clics
    nixosConfigurations.apprendys-installed = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = commonModules ++ [ ./profiles/installed.nix ];
    };
```

- [ ] **Step 4: Build du toplevel installé**

Run: `nix build .#nixosConfigurations.apprendys-installed.config.system.build.toplevel -L`
Expected: succès. C'est la closure qui sera embarquée dans l'ISO.

- [ ] **Step 5: Commit**

```bash
git add profiles/installed.nix modules/hardware-quirks.nix flake.nix
git commit -m "feat: profil apprendys-installed (labels, GRUB UEFI+legacy-ready, quirks I2C)"
```

---

### Task 9: L'installateur 3-clics

Script zenity : avertissement → choix disque interne + prénom + profil (Enfant/Adulte) → confirmation → sgdisk/mkfs/mount → `nixos-install --system` (offline, closure embarquée) → grub legacy si BIOS → prénom/profil écrits dans le home.

**Files:**
- Create: `packages/apprendys-installer.nix`
- Create: `modules/installer.nix`
- Modify: `flake.nix` (sortie `apprendys-installer-iso` + specialArgs)

- [ ] **Step 1: Écrire `packages/apprendys-installer.nix`**

```nix
{ lib
, writeShellApplication
, zenity
, gptfdisk        # sgdisk
, dosfstools      # mkfs.fat
, e2fsprogs       # mkfs.ext4
, util-linux      # lsblk, mount, wipefs
, nixos-install-tools
, coreutils
, installedSystem   # toplevel de nixosConfigurations.apprendys-installed (specialArgs)
}:

# Apprendys Installer — les « 3 clics » du Masterplan V3.
# Tourne sur l'ISO live. Cible : disques INTERNES uniquement (jamais l'USB live).

writeShellApplication {
  name = "apprendys-installer";
  runtimeInputs = [ zenity gptfdisk dosfstools e2fsprogs util-linux nixos-install-tools coreutils ];
  text = ''
    set -e

    # Élévation : règle sudo NOPASSWD dédiée (modules/installer.nix)
    if [ "$(id -u)" -ne 0 ]; then
      exec sudo -n "$0" "$@"
    fi
    export DISPLAY=''${DISPLAY:-:0}

    # ── CLIC 1 : avertissement ──
    zenity --question --width=460 --icon-name=dialog-warning \
      --title="Installer Apprendys" \
      --text="<b>Apprendys va être installé sur cet ordinateur.</b>\n\nTOUT le contenu du disque choisi sera <b>définitivement effacé</b>\n(Windows, photos, documents...).\n\nDurée : environ 20 minutes.\n\nContinuer ?" \
      --ok-label="Continuer" --cancel-label="Annuler" || exit 0

    # ── Disques internes (exclut l'USB live et les loop) ──
    mapfile -t DISKS < <(lsblk -dno NAME,SIZE,MODEL,TRAN | awk '$NF != "usb" && $1 !~ /^(loop|sr|zram)/ {print}')
    if [ "''${#DISKS[@]}" -eq 0 ]; then
      zenity --error --width=400 --text="Aucun disque interne détecté.\nCet ordinateur a-t-il bien un disque dur ?"
      exit 1
    fi

    LIST_ARGS=()
    for d in "''${DISKS[@]}"; do
      name=$(echo "$d" | awk '{print $1}')
      rest=$(echo "$d" | cut -d' ' -f2-)
      LIST_ARGS+=("FALSE" "/dev/$name" "$rest")
    done
    LIST_ARGS[0]="TRUE"   # pré-sélectionner le premier

    # ── CLIC 2 : disque + prénom + profil ──
    TARGET=$(zenity --list --radiolist --width=520 --height=300 \
      --title="Installer Apprendys — choisir le disque" \
      --text="Sur quel disque installer ? (il sera effacé)" \
      --column="" --column="Disque" --column="Taille / Modèle" \
      "''${LIST_ARGS[@]}") || exit 0

    FORM=$(zenity --forms --width=420 --title="Installer Apprendys — pour qui ?" \
      --text="Personnalisation" \
      --add-entry="Prénom" \
      --add-combo="Profil" --combo-values="Enfant|Adulte") || exit 0
    PRENOM=$(echo "$FORM" | cut -d'|' -f1)
    PROFIL=$(echo "$FORM" | cut -d'|' -f2)
    [ -n "$PRENOM" ] || PRENOM="Apprendys"
    ICONSET="junior"; [ "$PROFIL" = "Adulte" ] && ICONSET="adult"

    # ── CLIC 3 : confirmation finale ──
    zenity --question --width=460 --icon-name=dialog-warning \
      --title="Dernière vérification" \
      --text="Installer Apprendys pour <b>$PRENOM</b> ($PROFIL)\nsur <b>$TARGET</b> ?\n\n<b>Tout le contenu de $TARGET sera effacé. C'est définitif.</b>" \
      --ok-label="INSTALLER" --cancel-label="Annuler" || exit 0

    # ── Installation (barre de progression) ──
    {
      echo "5";  echo "# Préparation du disque..."
      wipefs -af "$TARGET" >/dev/null
      sgdisk -Z "$TARGET" >/dev/null
      sgdisk -n1:0:+1M   -t1:EF02 -c1:BIOSBOOT "$TARGET" >/dev/null
      sgdisk -n2:0:+512M -t2:EF00 -c2:ESP      "$TARGET" >/dev/null
      sgdisk -n3:0:0     -t3:8300 -c3:ROOT     "$TARGET" >/dev/null
      sleep 2  # laisser udev créer les nœuds
      P2=$(lsblk -pnro NAME "$TARGET" | sed -n 3p)
      P3=$(lsblk -pnro NAME "$TARGET" | sed -n 4p)

      echo "10"; echo "# Formatage..."
      mkfs.fat -F32 -n APPR-EFI "$P2" >/dev/null
      mkfs.ext4 -F -L APPRENDYS "$P3" >/dev/null

      echo "15"; echo "# Montage..."
      mount "$P3" /mnt
      mkdir -p /mnt/boot
      mount "$P2" /mnt/boot

      echo "20"; echo "# Copie du système (15-20 min, c'est normal)..."
      nixos-install --system ${installedSystem} --no-root-password --no-channel-copy >/dev/null 2>&1

      echo "85"; echo "# Démarrage BIOS ancien (si nécessaire)..."
      if [ ! -d /sys/firmware/efi ]; then
        nixos-enter --root /mnt -- grub-install --target=i386-pc "$TARGET" >/dev/null 2>&1 || true
      fi

      echo "92"; echo "# Personnalisation pour $PRENOM..."
      mkdir -p /mnt/home/apprendys/.config/apprendys
      printf '%s\n' "$PRENOM"  > /mnt/home/apprendys/.config/apprendys/user-name
      printf '%s\n' "$ICONSET" > /mnt/home/apprendys/.config/apprendys/icon-set
      chown -R 1000:100 /mnt/home/apprendys

      echo "98"; echo "# Finalisation..."
      umount -R /mnt
      echo "100"; echo "# Terminé !"
    } | zenity --progress --width=460 --title="Installation d'Apprendys" \
          --no-cancel --auto-close

    zenity --info --width=420 --title="C'est prêt !" \
      --text="<b>Apprendys est installé pour $PRENOM.</b>\n\n1. Retirez la clé USB\n2. Redémarrez l'ordinateur\n\nL'ordinateur démarrera directement sur Apprendys."
  '';
}
```

- [ ] **Step 2: Écrire `modules/installer.nix`**

```nix
{ config, pkgs, lib, installedSystem, ... }:
let
  apprendys-installer = pkgs.callPackage ../packages/apprendys-installer.nix {
    inherit installedSystem;
  };
in {
  # Embarque la closure COMPLÈTE du système installé dans l'ISO
  # → nixos-install 100 % offline chez le client (zéro réseau requis)
  system.extraDependencies = [ installedSystem ];

  environment.systemPackages = [ apprendys-installer pkgs.zenity ];

  # L'utilisateur live peut lancer l'installateur sans mot de passe — UNIQUEMENT lui
  security.sudo.enable = lib.mkForce true;
  security.sudo.extraRules = [{
    users = [ "apprendys" ];
    commands = [{
      command = "${apprendys-installer}/bin/apprendys-installer";
      options = [ "NOPASSWD" ];
    }];
  }];

  # Icône bureau — présente UNIQUEMENT sur l'ISO installeur
  home-manager.users.apprendys.home.file."Bureau/installer-apprendys.desktop" = {
    force = true;
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Installer Apprendys sur cet ordinateur
      Comment=Efface ce PC et installe Apprendys définitivement
      Exec=apprendys-installer
      Icon=system-software-install
      Terminal=false
    '';
  };
}
```

- [ ] **Step 3: Sortie ISO installeur dans `flake.nix`**

Dans `packages.${system}`, ajouter :

```nix
      # ISO installeur — LE produit du Masterplan V3 (clé 79 €)
      apprendys-installer-iso = nixos-generators.nixosGenerate {
        inherit system;
        format = "iso";
        specialArgs = {
          installedSystem =
            self.nixosConfigurations.apprendys-installed.config.system.build.toplevel;
        };
        modules = commonModules ++ usbModules ++ [
          ./profiles/light.nix
          ./modules/installer.nix
        ];
      };
```

- [ ] **Step 4: Build l'ISO installeur**

Run: `nix build .#apprendys-installer-iso -L`
Expected: succès. L'ISO fait ~3-4 Go (live + closure installée, large déduplication). Noter la taille : `ls -lh result/iso/`.

- [ ] **Step 5: Commit**

```bash
git add packages/apprendys-installer.nix modules/installer.nix flake.nix
git commit -m "feat: installateur 3-clics (zenity, sgdisk labels, nixos-install offline)"
```

---

### Task 10: Test bout-en-bout en VM neuve (UEFI puis legacy)

Le test qui valide le MVP : une VM vierge = le « vieux PC du placard ».

**Files:** aucun.

- [ ] **Step 1: Créer la VM de test UEFI avec l'ISO**

```bash
virt-install --connect qemu:///system --name apprendys-test-install \
  --memory 4096 --vcpus 2 --disk size=40 --os-variant generic \
  --cdrom "$(ls /home/florent/Documents/NixProj/apprendys-nix/result/iso/*.iso)" \
  --boot uefi --noautoconsole
virt-viewer --connect qemu:///system apprendys-test-install &
```
Expected: boot sur le bureau Apprendys live avec l'icône « Installer Apprendys sur cet ordinateur ».

- [ ] **Step 2: Dérouler les 3 clics**

Dans la console graphique : double-clic icône → avertissement → disque vda + prénom « Test » + profil Enfant → INSTALLER.
Expected: barre de progression, ~5-15 min en VM, dialog final « C'est prêt ! ».

- [ ] **Step 3: Reboot sur le disque**

```bash
virsh --connect qemu:///system destroy apprendys-test-install
virsh --connect qemu:///system edit apprendys-test-install   # retirer le cdrom du boot, ou :
virsh --connect qemu:///system start apprendys-test-install
```
Expected: GRUB → autologin → bureau XFCE Apprendys, **sans la clé/ISO**.

- [ ] **Step 4: Checklist fonctionnelle sur le système installé**

Dans la session installée :
- Sélectionner un texte dans Firefox → Ctrl+Espace → la voix Piper lit (vérifier audio VM activé).
- Ctrl+Maj+Espace → notification « Dictée activée ! » (micro VM absent : la notif suffit).
- LibreOffice Writer → menu LireCouleur présent.
- `cat ~/.config/apprendys/user-name` → `Test`.
- Pas de SSH : `ssh apprendys@<ip-vm-test>` → connexion refusée.
Expected: tout passe. Sinon → corriger la task fautive avant de continuer.

- [ ] **Step 5: Test legacy BIOS (SeaBIOS)**

```bash
virsh --connect qemu:///system undefine apprendys-test-install --nvram --remove-all-storage
virt-install --connect qemu:///system --name apprendys-test-bios \
  --memory 4096 --vcpus 2 --disk size=40 --os-variant generic \
  --cdrom "$(ls result/iso/*.iso)" --noautoconsole
```
(Sans `--boot uefi` = SeaBIOS.) Dérouler Steps 2-4.
Expected: identique — le `grub-install --target=i386-pc` du script prend le relais.

- [ ] **Step 6: Nettoyage + tag**

```bash
virsh --connect qemu:///system undefine apprendys-test-bios --remove-all-storage
git tag mvp-installer-valide-vm
```

---

### Task 11: OTA du système installé + repo GitHub

`nixos-rebuild switch --flake github:…` hebdomadaire avec délai aléatoire. Rollback = générations GRUB natives (5 au menu, cf. Task 8). Prérequis : le repo doit être accessible depuis les machines clientes.

**Files:**
- Create: `modules/ota-installed.nix`
- Modify: `profiles/installed.nix` (import)

- [ ] **Step 1: Publier le repo sur GitHub**

⚠️ **Vérifier avec Florent avant : public ou privé+token ?** (Masterplan : la valeur est dans la commodité, pas les bits — public recommandé, et l'OTA sans token est beaucoup plus simple.) Retirer d'abord la clé SSH de debug si souhaité (`base.nix`, `openssh.authorizedKeys` — c'est une clé publique, pas un secret, mais autant nettoyer).

```bash
cd /home/florent/Documents/NixProj/apprendys-nix
gh repo create Ikkitsuna/apprendys-nix --public --source . --push
```
Expected: repo en ligne, `git push` futur = canal OTA.

- [ ] **Step 2: Écrire `modules/ota-installed.nix`**

```nix
{ config, pkgs, lib, ... }: {
  # OTA Apprendys installé — MAJ silencieuse hebdomadaire.
  # Atomique : nouvelle génération NixOS ; si régression → rollback au menu GRUB.
  systemd.services.apprendys-ota = {
    description = "Apprendys — mise à jour système (nixos-rebuild)";
    serviceConfig = { Type = "oneshot"; };
    path = [ pkgs.nixos-rebuild pkgs.nix pkgs.git pkgs.coreutils ];
    script = ''
      # Pile CMOS morte → année fausse → SSL cassé (bug terrain V1) : on saute
      [ "$(date +%Y)" -ge 2026 ] || exit 0
      nixos-rebuild switch \
        --flake github:Ikkitsuna/apprendys-nix#apprendys-installed \
        --refresh \
        || echo "apprendys-ota: échec (réseau ?) — prochaine tentative au timer"
    '';
  };
  systemd.timers.apprendys-ota = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;          # rattrape si le PC était éteint
      RandomizedDelaySec = "2h";
    };
  };
}
```

- [ ] **Step 3: Importer dans `profiles/installed.nix`**

```nix
  imports = [ ../modules/hardware-quirks.nix ../modules/ota-installed.nix ];
```

- [ ] **Step 4: Rebuild de l'ISO (elle doit embarquer l'OTA) puis test sur une VM installée**

```bash
nix build .#apprendys-installer-iso -L
```
Refaire une install complète (Task 10 Steps 1-3) avec cette ISO, puis sur le système installé :
```bash
sudo systemctl start apprendys-ota
journalctl -u apprendys-ota --no-pager | tail -5
sudo nixos-rebuild list-generations | tail -3
```
Expected: le service tire le flake GitHub et reconstruit (ou « échec réseau » propre si offline) ; une nouvelle génération apparaît si un commit a été poussé entre-temps. Test rollback : reboot → menu GRUB → génération précédente → boot OK.

- [ ] **Step 5: Commit + push (le push EST le canal OTA désormais)**

```bash
git add modules/ota-installed.nix profiles/installed.nix
git commit -m "feat: OTA installée — nixos-rebuild hebdo, rollback générations GRUB"
git push
```

---

### Task 12: Durcissement pré-production + checklist matériel réel

**Files:**
- Create: `modules/release.nix`
- Modify: `flake.nix` (inclure release.nix dans l'ISO installeur)

- [ ] **Step 1: Écrire `modules/release.nix`** (neutralise le debug de `profiles/light.nix` sur l'ISO expédiée)

```nix
{ config, pkgs, lib, ... }: {
  # ISO de production : pas de porte d'entrée.
  # mkOverride 40 : passe devant les mkForce (50) de profiles/light.nix.
  services.openssh.enable = lib.mkOverride 40 false;
  security.sudo.wheelNeedsPassword = lib.mkOverride 40 true;
  users.users.apprendys.openssh.authorizedKeys.keys = lib.mkOverride 40 [ ];
}
```

- [ ] **Step 2: L'ajouter à l'ISO installeur dans `flake.nix`**

```nix
        modules = commonModules ++ usbModules ++ [
          ./profiles/light.nix
          ./modules/installer.nix
          ./modules/release.nix
        ];
```
NB : `modules/installer.nix` garde son `sudo NOPASSWD` ciblé sur le seul binaire installeur — c'est voulu.

- [ ] **Step 3: Rebuild + vérifier que SSH est bien mort sur l'ISO**

```bash
nix build .#apprendys-installer-iso -L
# Booter l'ISO en VM (Task 10 Step 1) puis :
ssh -o ConnectTimeout=3 apprendys@<ip-vm-live> ; echo "exit=$?"
```
Expected: connexion refusée/timeout, `exit≠0`.

- [ ] **Step 4: Commit + tag**

```bash
git add modules/release.nix flake.nix
git commit -m "feat: durcissement ISO production (SSH off, sudo restreint)"
git push && git tag mvp-iso-v1
```

- [ ] **Step 5: Checklist matériel réel (manuel, hors VM — à faire avec Florent)**

Flasher une clé : `sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync` puis dérouler la checklist Task 10 Step 4 sur :
- [ ] Le Blackview (référence terrain V1, BIOS Insyde 2015)
- [ ] Un PC UEFI récent
- [ ] Si dispo : un portable ALPS/Elan (validation rebind touchpad)
- [ ] Micro réel : dictée Vosk effective (Ctrl+Maj+Espace tape du texte)

Expected: install + boot + TTS/STT/LireCouleur OK partout. Chaque échec = issue GitHub avec modèle du PC.

---

## Ordre & dépendances

```
T1 (git) → T2 (nix host) → T3 (HM fix) → T4 (VM unifiée)
                                   ↓
                  T5 (vosk) → T6 (STT) → T7 (session-init)
                                   ↓
                          T8 (profil installé)
                                   ↓
                          T9 (installateur) → T10 (test VM) → T11 (OTA) → T12 (prod)
```

## Critère de fin (Masterplan §6, jalon 3 mois)

Une clé flashée avec `mvp-iso-v1` installe Apprendys en 3 clics sur un vieux PC réel, qui reboote sur un bureau fonctionnel (TTS, STT, LireCouleur, prénom de l'enfant), se met à jour tout seul via GitHub, et peut rollback par GRUB. → Le produit à 79 € existe ; la suite est commerciale (page web, dossier distributeurs), pas technique.
