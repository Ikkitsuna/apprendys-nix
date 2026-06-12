{ lib
, writeShellApplication
, zenity
, gptfdisk        # sgdisk
, dosfstools      # mkfs.fat
, e2fsprogs       # mkfs.ext4
, util-linux      # lsblk, mount, wipefs, partprobe (de util-linux), udevadm via systemd
, systemd         # udevadm
, parted          # partprobe (fiable cross-distro)
, nixos-install-tools
, coreutils
, gnused
, gnugrep
, installedSystem   # toplevel de nixosConfigurations.apprendys-installed (specialArgs)
}:

# Apprendys Installer — les « 3 clics » du Masterplan V3.
# Tourne sur l'ISO live. Cible : disques INTERNES uniquement (jamais l'USB live).
#
# Sécurité absolue (cf. exigences Task 9) :
#   - le disque USB live (TRAN=usb) n'apparaît JAMAIS dans la liste
#   - loop / sr / zram exclus ; tout le reste (sata/nvme/virtio/ata) accepté
#   - noms de partitions résolus robustement (sda3 vs nvme0n1p3 vs mmcblk0p3)
#   - toute panne pendant l'install → zenity --error + log, JAMAIS de retry auto
#   - labels EXACTS attendus par profiles/installed.nix : APPRENDYS / APPR-EFI

writeShellApplication {
  name = "apprendys-installer";
  runtimeInputs = [
    zenity gptfdisk dosfstools e2fsprogs util-linux systemd parted
    nixos-install-tools coreutils gnused gnugrep
  ];
  text = ''
    # writeShellApplication injecte déjà : set -euo pipefail

    LOG=/tmp/apprendys-install.log

    # ── Élévation : règle sudo NOPASSWD dédiée (modules/installer.nix) ──
    # On se ré-exécute via le chemin trouvé dans le PATH (symlink systemPackages
    # → /run/current-system/sw/bin/apprendys-installer). La règle sudoers couvre
    # CE chemin ET le chemin store : voir modules/installer.nix.
    if [ "$(id -u)" -ne 0 ]; then
      SELF="$(command -v apprendys-installer)"
      exec sudo -n --preserve-env=DISPLAY,XAUTHORITY "$SELF" "$@"
    fi

    # Création du log UNIQUEMENT en phase root, avec rm -f préalable : un log
    # résiduel appartenant à l'utilisateur rendrait toute écriture root impossible
    # (fs.protected_regular en /tmp sticky) → fausses « étapes échouées ».
    rm -f "$LOG"
    : > "$LOG"

    export DISPLAY="''${DISPLAY:-:0}"
    # Repli si XAUTHORITY n'a pas survécu : cookie SDDM puis ~/.Xauthority
    if [ -z "''${XAUTHORITY:-}" ]; then
      for f in /run/sddm/xauth_* /home/apprendys/.Xauthority; do
        [ -f "$f" ] && export XAUTHORITY="$f" && break
      done
    fi

    # Helper : message d'erreur fatal + log + sortie non-zéro
    fatal() {
      local msg="$1"
      printf '[FATAL] %s\n' "$msg" >> "$LOG" 2>/dev/null || true
      zenity --error --width=460 \
        --title="Installation Apprendys — erreur" \
        --text="<b>L'installation a échoué.</b>\n\n$msg\n\nLe disque peut être dans un état incomplet.\nNe redémarrez PAS sur ce disque.\n\nDétails techniques : $LOG" \
        2>/dev/null || true
      exit 1
    }

    # ── CLIC 1 : avertissement ──
    # Note : zenity renvoie rc=1 sur Annuler. Le `|| exit 0` ne doit PAS être
    # avalé par pipefail (pas de pipe ici, c'est sûr).
    if ! zenity --question --width=460 --icon-name=dialog-warning \
      --title="Installer Apprendys" \
      --text="<b>Apprendys va être installé sur cet ordinateur.</b>\n\nTOUT le contenu du disque choisi sera <b>définitivement effacé</b>\n(Windows, photos, documents...).\n\nDurée : environ 20 minutes.\n\nContinuer ?" \
      --ok-label="Continuer" --cancel-label="Annuler"; then
      exit 0
    fi

    # ── Disques internes (exclut l'USB live, loop, optique, zram) ──
    # lsblk -dn : périphériques de base seulement, sans en-tête.
    # Colonnes : NAME SIZE MODEL TRAN TYPE
    # Règle : on garde TYPE=disk, on rejette TRAN=usb, et les noms loop*/sr*/zram*.
    # En VM (Task 10) le disque est virtio → TRAN vide ou "virtio" → gardé. OK.
    build_disk_list() {
      # Lecture par champ — JAMAIS d'eval sur une sortie contenant des chaînes
      # contrôlées par le matériel (MODEL) : un firmware piégé = exécution root.
      local NAME SIZE MODEL TRAN TYPE
      while IFS= read -r NAME; do
        [ -n "$NAME" ] || continue
        case "$NAME" in
          loop*|sr*|zram*|fd*) continue ;;
        esac
        TYPE="$(lsblk -dno TYPE "/dev/$NAME" 2>/dev/null || true)"
        [ "$TYPE" = "disk" ] || continue
        TRAN="$(lsblk -dno TRAN "/dev/$NAME" 2>/dev/null || true)"
        [ "$TRAN" = "usb" ] && continue
        SIZE="$(lsblk -dno SIZE "/dev/$NAME" 2>/dev/null || true)"
        MODEL="$(lsblk -dno MODEL "/dev/$NAME" 2>/dev/null | tr -d '\000-\037' || true)"
        [ -z "$MODEL" ] && MODEL="(disque)"
        printf 'FALSE\n/dev/%s\n%s\n%s\n' "$NAME" "$SIZE" "$MODEL"
      done < <(lsblk -dno NAME 2>/dev/null)
    }

    DISK_ROWS="$(build_disk_list || true)"
    if [ -z "$DISK_ROWS" ]; then
      fatal "Aucun disque interne détecté.\nVérifiez que cet ordinateur a bien un disque dur ou SSD."
    fi

    # ── CLIC 2a : choix du disque (radiolist) ──
    # On passe les lignes via xargs-like : zenity --list lit ses colonnes en flux d'args.
    # mapfile pour préserver les champs.
    mapfile -t DISK_ARGS < <(printf '%s\n' "$DISK_ROWS")

    # --print-column=2 : la 1re colonne est le bouton radio (TRUE/FALSE) ;
    # sans cette option zenity renverrait "TRUE" au lieu du chemin disque.
    TARGET="$(zenity --list --radiolist --width=560 --height=340 \
      --title="Choisir le disque" \
      --text="Sur quel disque installer Apprendys ?\n<b>Tout son contenu sera effacé.</b>" \
      --column="" --column="Disque" --column="Taille" --column="Modèle" \
      --print-column=2 \
      "''${DISK_ARGS[@]}" 2>/dev/null)" || exit 0

    if [ -z "$TARGET" ]; then
      exit 0
    fi
    if [ ! -b "$TARGET" ]; then
      fatal "Le disque choisi ($TARGET) est introuvable."
    fi

    TARGET_DESC="$(lsblk -dno SIZE,MODEL "$TARGET" 2>/dev/null | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' | tr -s ' ' || true)"

    # ── CLIC 2b : prénom + profil (forms) ──
    FORM="$(zenity --forms --width=460 \
      --title="Personnaliser Apprendys" \
      --text="Encore deux informations :" \
      --add-entry="Prénom" \
      --add-combo="Profil" --combo-values="Enfant|Adulte" \
      2>/dev/null)" || exit 0

    # zenity --forms sépare les champs par '|'
    PRENOM="''${FORM%%|*}"
    PROFIL="''${FORM##*|}"

    # ── Sanitisation prénom : retire | et caractères de contrôle, trim ──
    # tr -d des contrôles ; sed retire | et espaces de bord ; défaut "Apprendys".
    PRENOM="$(printf '%s' "$PRENOM" | tr -d '\000-\037|' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$PRENOM" ] && PRENOM="Apprendys"

    # Variante sûre pour l'affichage Pango (zenity --question/--info en markup) :
    # & < > casseraient le rendu GTK. Le prénom RÉEL (non échappé) reste écrit tel quel
    # dans user-name plus bas.
    PRENOM_AFF="$(printf '%s' "$PRENOM" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"

    # Profil → icon-set (junior pour Enfant, adult pour Adulte). Défaut junior.
    case "$PROFIL" in
      Adulte) ICON_SET="adult" ;;
      *)      ICON_SET="junior" ;;
    esac

    # ── CLIC 3 : confirmation finale ──
    if ! zenity --question --width=480 --icon-name=dialog-warning \
      --title="Dernière vérification" \
      --text="<b>Récapitulatif</b>\n\nDisque : <b>$TARGET</b> ($TARGET_DESC)  (sera effacé)\nPrénom : <b>$PRENOM_AFF</b>\nProfil : <b>$PROFIL</b>\n\nC'est le dernier moment pour annuler.\nAprès « Installer », le disque sera effacé." \
      --ok-label="Installer" --cancel-label="Annuler"; then
      exit 0
    fi

    # ──────────────────────────────────────────────────────────────────────
    # INSTALLATION
    # Tout passe par une fonction `do_install` ; chaque étape critique est
    # estampillée dans STEP. En cas d'échec → fatal "$STEP". Aucun retry.
    # La sortie verbeuse (nixos-install) va dans $LOG, jamais dans le pipe progress.
    # ──────────────────────────────────────────────────────────────────────
    STEPFILE="$(mktemp)"
    trap 'rm -f "$STEPFILE"' EXIT

    do_install() {
      # $1 = TARGET. Émet des lignes "N\n#texte\n" pour zenity --progress.
      local TARGET="$1"

      log_step() { printf '%s\n' "$1" > "$STEPFILE"; printf '\n=== %s ===\n' "$1" >> "$LOG"; }

      # Re-run propre : démonter tout reliquat d'une tentative précédente
      # (sinon partprobe EBUSY → table non relue → résolution de partition faussée).
      umount -R /mnt >>"$LOG" 2>&1 || true

      echo "2" ; echo "# Préparation du disque..."
      # Piège classique : le bureau live (automount udisks/thunar) peut avoir monté
      # des partitions du disque cible — surtout à la 2e tentative après un essai
      # qui a déjà créé des partitions. wipefs/sgdisk échouent alors avec EBUSY.
      # On libère le disque cible d'abord : démontage forcé + swapoff de CHAQUE partition.
      log_step "Libération du disque cible (démontage des partitions)"
      for _part in $(lsblk -lnro NAME "$TARGET" 2>/dev/null | tail -n +2); do
        umount -f "/dev/$_part" >>"$LOG" 2>&1 || umount -l "/dev/$_part" >>"$LOG" 2>&1 || true
        swapoff "/dev/$_part" >>"$LOG" 2>&1 || true
      done
      log_step "Effacement des signatures (wipefs)"
      wipefs -af "$TARGET" >>"$LOG" 2>&1 || return 1
      log_step "Effacement de la table de partitions (sgdisk -Z)"
      sgdisk -Z "$TARGET" >>"$LOG" 2>&1 || return 1

      echo "10" ; echo "# Création des partitions..."
      log_step "Création des partitions (sgdisk)"
      # 1: BIOS boot (EF02, 1M) — requis pour grub legacy sur table GPT
      # 2: ESP (EF00, 512M) — label APPR-EFI
      # 3: root (8300, reste) — label APPRENDYS
      sgdisk \
        -n1:0:+1M    -t1:EF02 -c1:"BIOS" \
        -n2:0:+512M  -t2:EF00 -c2:"ESP" \
        -n3:0:0      -t3:8300 -c3:"ROOT" \
        "$TARGET" >>"$LOG" 2>&1 || return 1

      log_step "Relecture de la table de partitions"
      partprobe "$TARGET" >>"$LOG" 2>&1 || true
      udevadm settle >>"$LOG" 2>&1 || true
      sleep 2

      # ── Résolution robuste des noms de partitions ──
      # nvme0n1 → nvme0n1p2/p3 ; mmcblk0 → mmcblk0p2/p3 ; sda → sda2/sda3.
      # Règle : si le dernier caractère du device est un chiffre, séparateur "p".
      echo "18" ; echo "# Vérification des partitions..."
      log_step "Résolution des noms de partitions"
      local SEP=""
      case "$TARGET" in
        *[0-9]) SEP="p" ;;
      esac
      local ESP="''${TARGET}''${SEP}2"
      local ROOT="''${TARGET}''${SEP}3"

      # Vérifier que les partitions existent VRAIMENT (sinon abort avant mkfs)
      if [ ! -b "$ESP" ] || [ ! -b "$ROOT" ]; then
        printf 'Partitions attendues introuvables : ESP=%s ROOT=%s\n' "$ESP" "$ROOT" >> "$LOG"
        # Dernier recours : lister via lsblk -pnro (lignes 3 et 4 du device)
        ESP="$(lsblk -pnro NAME "$TARGET" 2>/dev/null | sed -n '3p')"
        ROOT="$(lsblk -pnro NAME "$TARGET" 2>/dev/null | sed -n '4p')"
        printf 'Repli lsblk : ESP=%s ROOT=%s\n' "$ESP" "$ROOT" >> "$LOG"
      fi
      if [ -z "$ESP" ] || [ -z "$ROOT" ] || [ ! -b "$ESP" ] || [ ! -b "$ROOT" ]; then
        return 1
      fi

      echo "22" ; echo "# Formatage des partitions..."
      # Labels EXACTS attendus par profiles/installed.nix.
      log_step "Formatage ESP (mkfs.fat APPR-EFI)"
      mkfs.fat -F32 -n APPR-EFI "$ESP" >>"$LOG" 2>&1 || return 1
      log_step "Formatage root (mkfs.ext4 APPRENDYS)"
      mkfs.ext4 -F -L APPRENDYS "$ROOT" >>"$LOG" 2>&1 || return 1

      echo "28" ; echo "# Montage..."
      # Juste après mkfs, udev re-sonde encore les partitions : sans settle,
      # mount voit une vue périmée et échoue (« superbloc erroné » reproduit
      # en VM). Type explicite + 3 tentatives = montage déterministe.
      log_step "Synchronisation udev (settle)"
      udevadm settle >>"$LOG" 2>&1 || true
      log_step "Montage de la racine sur /mnt"
      umount -R /mnt >>"$LOG" 2>&1 || true
      mkdir -p /mnt >>"$LOG" 2>&1 || true
      local MNT_OK=0 _try
      for _try in 1 2 3; do
        if mount -t ext4 "$ROOT" /mnt >>"$LOG" 2>&1; then MNT_OK=1; break; fi
        sleep 2
        udevadm settle >>"$LOG" 2>&1 || true
      done
      [ "$MNT_OK" = 1 ] || return 1
      mkdir -p /mnt/boot >>"$LOG" 2>&1 || return 1
      log_step "Montage de /mnt/boot"
      MNT_OK=0
      for _try in 1 2 3; do
        if mount -t vfat "$ESP" /mnt/boot >>"$LOG" 2>&1; then MNT_OK=1; break; fi
        sleep 2
        udevadm settle >>"$LOG" 2>&1 || true
      done
      [ "$MNT_OK" = 1 ] || return 1

      echo "35" ; echo "# Installation du système (long, ~15 min)..."
      log_step "Installation NixOS (nixos-install, offline)"
      # --system : closure embarquée dans l'ISO (system.extraDependencies).
      # --no-channel-copy : pas de réseau. --no-root-password : compte root verrouillé.
      nixos-install \
        --root /mnt \
        --system "${installedSystem}" \
        --no-root-password \
        --no-channel-copy >>"$LOG" 2>&1 || return 1

      echo "82" ; echo "# Configuration du démarrage..."
      # GRUB UEFI est posé par nixos-install (boot.loader.grub efiSupport=true,
      # efiInstallAsRemovable). En BIOS legacy (/sys/firmware/efi absent), il faut
      # installer GRUB i386-pc sur le MBR du disque cible.
      if [ ! -d /sys/firmware/efi ]; then
        log_step "Installation GRUB legacy BIOS (i386-pc)"
        nixos-enter --root /mnt -- /run/current-system/sw/bin/grub-install \
          --target=i386-pc "$TARGET" >>"$LOG" 2>&1 || return 1
      fi

      echo "90" ; echo "# Personnalisation..."
      log_step "Écriture du prénom et du profil"
      # IMPORTANT : on écrit dans /var/lib/apprendys (persistant, NON géré par
      # home-manager). Écrire dans le home avant le 1er boot ne survit PAS à
      # l'activation home-manager — les fichiers seraient effacés au démarrage.
      # session-init seed ~/.config/apprendys/ depuis ici au 1er login.
      mkdir -p /mnt/var/lib/apprendys >>"$LOG" 2>&1 || return 1
      printf '%s\n' "$PRENOM"   > /mnt/var/lib/apprendys/user-name || return 1
      printf '%s\n' "$ICON_SET" > /mnt/var/lib/apprendys/profile   || return 1
      chmod 755 /mnt/var/lib/apprendys >>"$LOG" 2>&1 || true
      chmod 644 /mnt/var/lib/apprendys/user-name /mnt/var/lib/apprendys/profile >>"$LOG" 2>&1 || true

      echo "96" ; echo "# Finalisation..."
      log_step "Démontage"
      sync
      umount -R /mnt >>"$LOG" 2>&1 || true

      echo "100" ; echo "# Terminé."
      log_step "OK"
      return 0
    }

    # On exécute do_install dans le pipe progress. pipefail : si do_install
    # renvoie != 0, le statut du pipe est non-zéro → on lit STEPFILE pour le détail.
    # --no-cancel : pas d'annulation pendant l'écriture disque (irréversible).
    set +e
    do_install "$TARGET" | zenity --progress --no-cancel --auto-close \
      --width=480 --title="Installation d'Apprendys" \
      --text="Préparation..." --percentage=0
    RC=''${PIPESTATUS[0]}
    set -e

    if [ "$RC" -ne 0 ]; then
      FAILED_STEP="$(cat "$STEPFILE" 2>/dev/null || echo 'étape inconnue')"
      # Démontage best-effort pour ne pas laisser /mnt occupé
      umount -R /mnt >/dev/null 2>&1 || true
      fatal "Étape échouée : $FAILED_STEP"
    fi

    # ── Dialog final ──
    zenity --info --width=460 \
      --title="Apprendys est installé !" \
      --text="<b>C'est terminé.</b>\n\n1. Retirez la clé USB Apprendys.\n2. Cliquez sur OK puis redémarrez l'ordinateur.\n\nApprendys démarrera tout seul." \
      2>/dev/null || true

    exit 0
  '';
}
