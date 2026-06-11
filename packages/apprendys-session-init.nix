{ lib
, writeShellApplication
, lirecouleur     # injecté par apps.nix
, libreoffice-fresh
, coreutils
, findutils
, xrandr          # xorg.xrandr — injecté par apps.nix
, glib             # gio
, procps           # pkill
}:

# Apprendys session-init — lancé à chaque ouverture de session XFCE (autostart).
# Port du V1 patches/usr/local/bin/apprendys-session-init.sh + améliorations NixOS :
#
# 1. Active le set d'icônes (junior/teen/adult) selon ~/.config/apprendys/icon-set
#    cp --no-preserve=mode : les PNGs venant de symlinks Nix store sont 0444,
#    sans cette option un 2e passage échoue sur les fichiers read-only
# 2. Installe LireCouleur côté user via unopkg (une seule fois, flag sentinel)
# 3. Nettoie les locks stale Firefox/Chromium (V1 terrain : crash/coupure)
# 4. Brise les symlinks Nix store sur les .desktop Bureau (trusted exécutables)
# 5. Wallpaper dynamique — détecte le vrai nom du moniteur via xrandr
# 6. Panel XFCE fond noir + taille menu Whisker adaptée à la résolution
# 7. Icônes bureau xfce4-desktop + redémarrage xfdesktop

writeShellApplication {
  name = "apprendys-session-init";
  runtimeInputs = [
    libreoffice-fresh  # unopkg
    coreutils          # cp, rm, sha256sum, mkdir, touch, seq, sleep
    findutils          # find
    glib               # gio
    procps             # pkill
    xrandr             # xrandr (xorg.xrandr)
    # xfconf-query, xfce4-panel, xfdesktop : fournis par la session XFCE en cours
  ];
  text = ''
    set +e  # tolérance pannes — ne jamais crasher la session

    CONFIG_DIR="$HOME/.config/apprendys"
    ICON_BASE="$HOME/.local/share/icons/apprendys"
    mkdir -p "$CONFIG_DIR"

    # ── 1. Set d'icônes actif (junior | teen | adult) ──────────────────────────
    # tr -cd 'a-zA-Z' : supprime espaces, newlines, caractères invalides
    SET="junior"
    if [ -f "$CONFIG_DIR/icon-set" ]; then
      SET=$(tr -cd 'a-zA-Z' < "$CONFIG_DIR/icon-set")
    fi
    # Valider que le set demandé existe, sinon revenir au défaut
    [ -d "$ICON_BASE/$SET" ] || SET="junior"

    if [ -d "$ICON_BASE/$SET" ]; then
      # --no-preserve=mode : les PNGs venant de symlinks Nix store sont 0444 ;
      # sans cette option, un 2e passage cp -f échoue (permission denied)
      cp -f --no-preserve=mode "$ICON_BASE/$SET"/*.png "$ICON_BASE/" 2>/dev/null || true
    fi

    # ── 2. LireCouleur (une fois par user — flag sentinel) ──────────────────────
    # --suppress-license : évite l'invite interactive de licence (CC-BY acceptée par l'admin)
    if [ ! -f "$CONFIG_DIR/lirecouleur_installed" ]; then
      if unopkg add --suppress-license "${lirecouleur}/share/lirecouleur/lirecouleur.oxt" 2>/dev/null; then
        touch "$CONFIG_DIR/lirecouleur_installed"
      fi
    fi

    # ── 3. Locks stale (V1 terrain : crash/coupure → app refuse de démarrer) ───
    find "$HOME/.mozilla" -name ".parentlock" -delete 2>/dev/null || true
    rm -f "$HOME/.config/chromium/SingletonLock" \
          "$HOME/.config/chromium/SingletonSocket" \
          "$HOME/.config/chromium/SingletonCookie" 2>/dev/null || true

    # ── 4. Briser les symlinks Nix store → vrais fichiers writables ─────────────
    # chmod 755 requis : gio set (xattr trusted) échoue sur fichier non-writable
    for f in "$HOME/Bureau/"*.desktop; do
      [ -f "$f" ] || continue
      if [ -L "$f" ] || [ ! -w "$f" ]; then
        cp --remove-destination "$(readlink -f "$f" 2>/dev/null || echo "$f")" "$f" 2>/dev/null || true
        chmod 755 "$f" 2>/dev/null || true
      fi
    done

    # Trust des .desktop bureau — attendre que GVfs soit prêt (max 15s)
    for _retry in $(seq 1 15); do
      gio info "$HOME/Bureau/mes-devoirs.desktop" >/dev/null 2>&1 && break
      sleep 1
    done

    # XFCE 4.18 exige trusted=true ET xfce-exe-checksum=SHA256(contenu)
    for f in "$HOME/Bureau/mes-devoirs.desktop" \
             "$HOME/Bureau/je-recherche.desktop" \
             "$HOME/Bureau/mes-lecons.desktop"; do
      [ -f "$f" ] || continue
      CHKSUM=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)
      gio set "$f" metadata::trusted true 2>/dev/null || true
      [ -n "$CHKSUM" ] && gio set "$f" metadata::xfce-exe-checksum "$CHKSUM" 2>/dev/null || true
    done

    # ── 5. Wallpaper dynamique — détecte le vrai nom du moniteur ───────────────
    WALLPAPER="$HOME/.local/share/backgrounds/apprendys-wallpaper.png"
    if [ -f "$WALLPAPER" ]; then
      while IFS= read -r monitor; do
        for ws in 0 1 2 3; do
          xfconf-query -c xfce4-desktop \
            -p "/backdrop/screen0/monitor''${monitor}/workspace''${ws}/last-image" \
            -s "$WALLPAPER" --create -t string 2>/dev/null || true
          xfconf-query -c xfce4-desktop \
            -p "/backdrop/screen0/monitor''${monitor}/workspace''${ws}/image-style" \
            -s 5 --create -t int 2>/dev/null || true
        done
      done < <(xrandr --listmonitors 2>/dev/null | tail -n +2 | awk '{print $NF}')
    fi

    # ── 6. Panel fond noir + taille menu Whisker ────────────────────────────────
    xfconf-query -c xfce4-panel -p /panels/panel-1/background-style -t uint   -s 1          --create 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-1/background-style           -s 1                   2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-1/background-color -t string -s '#000000ff' --create 2>/dev/null || true
    xfconf-query -c xfce4-panel -p /panels/panel-1/background-color           -s '#000000ff'         2>/dev/null || true
    xfce4-panel --restart 2>/dev/null &

    SCREEN_W=$(xrandr --current 2>/dev/null \
      | awk '/ connected.*[0-9]+x[0-9]+/{match($0,/[0-9]+x[0-9]+/); print substr($0,RSTART,RLENGTH)}' \
      | cut -dx -f1 | head -1)
    if [ -n "$SCREEN_W" ] && [ "$SCREEN_W" -gt 0 ] 2>/dev/null; then
      MENU_W=$(( SCREEN_W * 45 / 100 ))
      MENU_H=$(( MENU_W * 67 / 100 ))
      xfconf-query -c xfce4-panel -p /plugins/plugin-1/menu-width  -t int -s "$MENU_W" --create 2>/dev/null || true
      xfconf-query -c xfce4-panel -p /plugins/plugin-1/menu-height -t int -s "$MENU_H" --create 2>/dev/null || true
      xfconf-query -c xfce4-panel -p /plugins/plugin-1/menu-width            -s "$MENU_W"         2>/dev/null || true
      xfconf-query -c xfce4-panel -p /plugins/plugin-1/menu-height           -s "$MENU_H"         2>/dev/null || true
    fi

    # ── 7. Icônes bureau xfce4-desktop ─────────────────────────────────────────
    xfconf-query -c xfce4-desktop -p /desktop-icons/style              -t int  -s 2     --create 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/icon-size          -t uint -s 72    --create 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home       -t bool -s false --create 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-trash      -t bool -s false --create 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -t bool -s false --create 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-removable  -t bool -s false --create 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/style              -s 2     2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home       -s false 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-trash      -s false 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -s false 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-removable  -s false 2>/dev/null || true

    # Redémarrer xfdesktop pour appliquer trust + wallpaper + icônes corrigées
    pkill xfdesktop 2>/dev/null || true
    sleep 1
    xfdesktop &

    exit 0
  '';
}
