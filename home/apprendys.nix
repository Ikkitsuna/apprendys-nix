{ config, pkgs, lib, ... }: {

  home.stateVersion = "24.11";
  home.username = "apprendys";
  home.homeDirectory = "/home/apprendys";

  # ── Wallpaper ────────────────────────────────────────────────────────────────
  home.file.".local/share/backgrounds/apprendys-wallpaper.png".source =
    ../assets/wallpaper/apprendys-wallpaper.png;

  # ── Icône menu Whisker ──────────────────────────────────────────────────────
  home.file.".local/share/icons/apprendys-menu.png".source =
    ../assets/icons/apprendys-menu.png;

  # ── Icônes profils (junior/teen/adult) ──────────────────────────────────────
  # Chaque set est déployé dans son sous-dossier.
  # session-init copie le set actif vers la racine (~/.local/share/icons/apprendys/)
  # que les .desktop Bureau et panel référencent (chemin sans sous-dossier, comme V1).
  home.file.".local/share/icons/apprendys/junior" = {
    source = ../assets/icons/junior;
    recursive = true;
  };
  home.file.".local/share/icons/apprendys/teen" = {
    source = ../assets/icons/teen;
    recursive = true;
  };
  home.file.".local/share/icons/apprendys/adult" = {
    source = ../assets/icons/adult;
    recursive = true;
  };

  # ── Bureau (Desktop XDG FR) — 3 icônes comme V1 ────────────────────────────
  # Les icônes pointent vers la racine (copiée par session-init selon profil actif)
  home.file."Bureau/mes-devoirs.desktop" = {
    force = true;   # fichier pré-existant sur les systèmes migrés — HM doit écraser
    text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Mes Devoirs
      Comment=Ouvre Xournal++ pour ecrire et dessiner
      Exec=xournalpp
      Icon=/home/apprendys/.local/share/icons/apprendys/mes-devoirs.png
      Terminal=false
      Categories=Education;
      StartupNotify=true
    '';
    executable = true;
  };

  home.file."Bureau/je-recherche.desktop" = {
    force = true;   # fichier pré-existant sur les systèmes migrés — HM doit écraser
    text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Je Recherche
      Comment=Ouvre le navigateur pour faire des recherches
      Exec=firefox
      Icon=/home/apprendys/.local/share/icons/apprendys/je-recherche.png
      Terminal=false
      Categories=Network;WebBrowser;
      StartupNotify=true
    '';
    executable = true;
  };

  home.file."Bureau/mes-lecons.desktop" = {
    force = true;   # fichier pré-existant sur les systèmes migrés — HM doit écraser
    text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Mes Lecons
      Comment=Ouvre LibreOffice Writer avec LireCouleur
      Exec=libreoffice --writer
      Icon=/home/apprendys/.local/share/icons/apprendys/mes-lecons.png
      Terminal=false
      Categories=Education;Office;
      StartupNotify=true
    '';
    executable = true;
  };

  # Launchers panel écrits dans home.activation (vrais fichiers, pas symlinks HM)
  # → évite l'accumulation de fichiers numérotés créés par xfce4-panel

  # ── ~/.local/share/applications — TTS/STT accessibles depuis menu ───────────
  home.file.".local/share/applications/apprendys-tts.desktop" = {
    text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Lis-Moi
      Comment=Selectionne du texte et je le lis (Ctrl+Espace)
      Exec=apprendys-tts
      Icon=/home/apprendys/.local/share/icons/apprendys/lis-moi.png
      Terminal=false
      Categories=Accessibility;
      StartupNotify=false
    '';
  };

  home.file.".local/share/applications/apprendys-stt.desktop" = {
    text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Je Dicte
      Comment=Parle et j ecris pour toi (Ctrl+Shift+Espace)
      Exec=apprendys-stt
      Icon=/home/apprendys/.local/share/icons/apprendys/je-dicte.png
      Terminal=false
      Categories=Accessibility;
      StartupNotify=false
    '';
  };

  # ── Config XDG user dirs ─────────────────────────────────────────────────────
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    setSessionVariables = true;
    desktop = "${config.home.homeDirectory}/Bureau";
    documents = "${config.home.homeDirectory}/Devoirs";
    download = "${config.home.homeDirectory}/Devoirs";
    music = "${config.home.homeDirectory}/Devoirs/Musique";
    pictures = "${config.home.homeDirectory}/Devoirs/Images";
    videos = "${config.home.homeDirectory}/Devoirs/Videos";
    publicShare = "${config.home.homeDirectory}/Bureau";
    templates = "${config.home.homeDirectory}/Bureau";
  };

  # ── XFCE4 — écriture directe des XML xfconf ─────────────────────────────────
  # xfconf-query --create ne met pas à jour les propriétés existantes.
  # On écrase les fichiers XML directement — lus par xfconfd au démarrage de session.
  home.activation.xfceConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    XFCONF_DIR="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$XFCONF_DIR"

    # ── Launchers panel — vrais fichiers, pas symlinks (évite doublons xfce) ─
    ICON_DIR="$HOME/.local/share/icons/apprendys"
    for N in 15 16 17; do
      DIR="$HOME/.config/xfce4/panel/launcher-$N"
      mkdir -p "$DIR"
      # Supprimer tous les fichiers numérotés créés par xfce4-panel
      find "$DIR" -maxdepth 1 -name '[0-9]*.desktop' -delete 2>/dev/null
    done

    cat > "$HOME/.config/xfce4/panel/launcher-15/apprendys-tts.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Lis-Moi
Comment=Lis le texte selectionne (Ctrl+Espace)
Exec=apprendys-tts
Icon=/home/apprendys/.local/share/icons/apprendys/lis-moi.png
Terminal=false
StartupNotify=false
EOF
    chmod 755 "$HOME/.config/xfce4/panel/launcher-15/apprendys-tts.desktop"

    cat > "$HOME/.config/xfce4/panel/launcher-16/apprendys-stt.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Je Dicte
Comment=Parle et j ecris pour toi (Ctrl+Shift+Espace)
Exec=apprendys-stt
Icon=/home/apprendys/.local/share/icons/apprendys/je-dicte.png
Terminal=false
StartupNotify=false
EOF
    chmod 755 "$HOME/.config/xfce4/panel/launcher-16/apprendys-stt.desktop"

    cat > "$HOME/.config/xfce4/panel/launcher-17/mes-fichiers.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Mes Fichiers
Comment=Ouvre le dossier Devoirs
Exec=thunar /home/apprendys/Devoirs
Icon=/home/apprendys/.local/share/icons/apprendys/mes-fichiers.png
Terminal=false
StartupNotify=true
EOF
    chmod 755 "$HOME/.config/xfce4/panel/launcher-17/mes-fichiers.desktop"

    # ── xfce4-panel.xml ───────────────────────────────────────────────────
    cat > "$XFCONF_DIR/xfce4-panel.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="48"/>
      <property name="icon-size" type="uint" value="32"/>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-color" type="string" value="#000000ff"/>
      <property name="enter-opacity" type="uint" value="100"/>
      <property name="leave-opacity" type="uint" value="100"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="17"/>
        <value type="int" value="15"/>
        <value type="int" value="16"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="12"/>
        <value type="int" value="13"/>
        <value type="int" value="14"/>
        <value type="int" value="99"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu">
      <property name="button-icon" type="string" value="/home/apprendys/.local/share/icons/apprendys-menu.png"/>
      <property name="button-title" type="string" value="Menu"/>
      <property name="show-button-title" type="bool" value="false"/>

      <property name="favorites" type="array">
        <value type="string" value="libreoffice-writer.desktop"/>
        <value type="string" value="firefox.desktop"/>
        <value type="string" value="org.gnome.Calculator.desktop"/>
      </property>
      <property name="hover-switch-category" type="bool" value="true"/>
      <property name="position-search-alternate" type="bool" value="true"/>
      <property name="position-categories-alternate" type="bool" value="true"/>
    </property>
    <property name="plugin-2" type="string" value="showdesktop"/>
    <property name="plugin-17" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="mes-fichiers.desktop"/>
      </property>
    </property>
    <property name="plugin-15" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="apprendys-tts.desktop"/>
      </property>
    </property>
    <property name="plugin-16" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="apprendys-stt.desktop"/>
      </property>
    </property>
    <property name="plugin-6" type="string" value="tasklist">
      <property name="show-handle" type="bool" value="false"/>
      <property name="middle-click" type="uint" value="0"/>
    </property>
    <property name="plugin-7" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-8" type="string" value="systray">
      <property name="icon-size" type="uint" value="22"/>
      <property name="show-frame" type="bool" value="false"/>
    </property>
    <property name="plugin-12" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="enable-mpris" type="bool" value="false"/>
      <property name="show-notifications" type="bool" value="true"/>
      <property name="enable-multimedia-keys" type="bool" value="false"/>
    </property>
    <property name="plugin-13" type="string" value="clock">
      <property name="digital-time-format" type="string" value="%H:%M"/>
      <property name="digital-layout" type="uint" value="3"/>
      <property name="digital-time-font" type="string" value="Luciole Bold 18"/>
    </property>
    <property name="plugin-14" type="string" value="power-manager-plugin"/>
    <property name="plugin-99" type="string" value="actions">
      <property name="appearance" type="uint" value="0"/>
      <property name="items" type="array">
        <value type="string" value="-logout"/>
        <value type="string" value="+shutdown"/>
        <value type="string" value="-restart"/>
        <value type="string" value="-suspend"/>
        <value type="string" value="-hibernate"/>
        <value type="string" value="-switch-user"/>
        <value type="string" value="-lock-screen"/>
      </property>
    </property>
  </property>
</channel>
XMLEOF

    # ── xfce4-keyboard-shortcuts.xml — V1 exact ───────────────────────────
    cat > "$XFCONF_DIR/xfce4-keyboard-shortcuts.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="custom" type="empty">
      <property name="&lt;Alt&gt;F2" type="string" value="xfce4-appfinder --collapsed">
        <property name="startup-notify" type="bool" value="true"/>
      </property>
      <property name="&lt;Alt&gt;Print" type="string" value="xfce4-screenshooter -w"/>
      <property name="&lt;Super&gt;r" type="string" value="xfce4-appfinder -c">
        <property name="startup-notify" type="bool" value="true"/>
      </property>
      <property name="XF86WWW" type="string" value="exo-open --launch WebBrowser"/>
      <property name="XF86Mail" type="string" value="exo-open --launch MailReader"/>
      <property name="&lt;Alt&gt;F3" type="string" value="xfce4-appfinder">
        <property name="startup-notify" type="bool" value="true"/>
      </property>
      <property name="Print" type="string" value="xfce4-screenshooter"/>
      <property name="&lt;Primary&gt;Escape" type="string" value="xfdesktop --menu"/>
      <property name="&lt;Shift&gt;Print" type="string" value="xfce4-screenshooter -r"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;Delete" type="string" value="xflock4"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;t" type="string" value="x-terminal-emulator"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;f" type="string" value="thunar"/>
      <property name="Super_L" type="string" value="xfce4-popup-whiskermenu"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;l" type="string" value="xflock4"/>
      <property name="&lt;Alt&gt;F1" type="string" value="xfce4-popup-applicationsmenu"/>
      <property name="&lt;Super&gt;p" type="string" value="xfce4-display-settings --minimal"/>
      <property name="&lt;Primary&gt;&lt;Shift&gt;Escape" type="string" value="xfce4-taskmanager"/>
      <property name="&lt;Super&gt;e" type="string" value="thunar"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;Escape" type="string" value="xkill"/>
      <property name="HomePage" type="string" value="exo-open --launch WebBrowser"/>
      <property name="XF86Display" type="string" value="xfce4-display-settings --minimal"/>
      <property name="override" type="bool" value="true"/>
      <property name="&lt;Primary&gt;space" type="string" value="apprendys-tts"/>
      <property name="&lt;Primary&gt;&lt;Shift&gt;space" type="string" value="apprendys-stt"/>
    </property>
  </property>
  <property name="xfwm4" type="empty">
    <property name="custom" type="empty">
      <property name="&lt;Alt&gt;F4" type="string" value="close_window_key"/>
      <property name="&lt;Alt&gt;F6" type="string" value="stick_window_key"/>
      <property name="&lt;Alt&gt;F7" type="string" value="move_window_key"/>
      <property name="&lt;Alt&gt;F8" type="string" value="resize_window_key"/>
      <property name="&lt;Alt&gt;F9" type="string" value="hide_window_key"/>
      <property name="&lt;Alt&gt;F10" type="string" value="maximize_window_key"/>
      <property name="&lt;Alt&gt;F11" type="string" value="fullscreen_key"/>
      <property name="&lt;Alt&gt;F12" type="string" value="above_key"/>
      <property name="&lt;Alt&gt;Tab" type="string" value="cycle_windows_key"/>
      <property name="&lt;Alt&gt;&lt;Shift&gt;Tab" type="string" value="cycle_reverse_windows_key"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;d" type="string" value="show_desktop_key"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;Left" type="string" value="left_workspace_key"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;Right" type="string" value="right_workspace_key"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;Up" type="string" value="up_workspace_key"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;Down" type="string" value="down_workspace_key"/>
      <property name="&lt;Super&gt;KP_Left" type="string" value="tile_left_key"/>
      <property name="&lt;Super&gt;KP_Right" type="string" value="tile_right_key"/>
      <property name="&lt;Super&gt;KP_Up" type="string" value="tile_up_key"/>
      <property name="&lt;Super&gt;KP_Down" type="string" value="tile_down_key"/>
      <property name="override" type="bool" value="true"/>
    </property>
  </property>
</channel>
XMLEOF

    # ── xfwm4.xml — police fenêtres DYS ──────────────────────────────────
    cat > "$XFCONF_DIR/xfwm4.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="title_font" type="string" value="Luciole Bold 13"/>
    <property name="cycle_raise" type="bool" value="false"/>
    <property name="zoom_desktop" type="bool" value="true"/>
    <property name="zoom_pointer" type="bool" value="true"/>
    <property name="vblank_mode" type="string" value="auto"/>
  </property>
</channel>
XMLEOF

    # ── xsettings.xml — police GTK système ────────────────────────────────
    cat > "$XFCONF_DIR/xsettings.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="DoubleClickTime" type="int" value="600"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Luciole 13"/>
    <property name="CursorThemeSize" type="int" value="48"/>
  </property>
</channel>
XMLEOF

    # ── xfce4-desktop.xml — fond d'écran + icônes bureau ─────────────────
    # Couvre tous les noms de moniteurs courants (VM, laptop, desktop)
    WALLPAPER="$HOME/.local/share/backgrounds/apprendys-wallpaper.png"
    cat > "$XFCONF_DIR/xfce4-desktop.xml" << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="$WALLPAPER"/>
        <property name="last-image" type="string" value="$WALLPAPER"/>
      </property>
      <property name="monitor1" type="empty">
        <property name="image-path" type="string" value="$WALLPAPER"/>
        <property name="last-image" type="string" value="$WALLPAPER"/>
      </property>
      <property name="monitorVirtual-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="$WALLPAPER"/>
        </property>
        <property name="workspace1" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="$WALLPAPER"/>
        </property>
        <property name="workspace2" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="$WALLPAPER"/>
        </property>
        <property name="workspace3" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="$WALLPAPER"/>
        </property>
      </property>
      <property name="monitoreDP-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="$WALLPAPER"/>
        </property>
      </property>
      <property name="monitorHDMI-1" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="$WALLPAPER"/>
        </property>
      </property>
    </property>
  </property>
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="2"/>
    <property name="icon-size" type="uint" value="72"/>
    <property name="font-size" type="double" value="12"/>
    <property name="file-icons" type="empty">
      <property name="show-home" type="bool" value="false"/>
      <property name="show-filesystem" type="bool" value="false"/>
      <property name="show-trash" type="bool" value="false"/>
      <property name="show-removable" type="bool" value="false"/>
    </property>
  </property>
</channel>
XMLEOF

    # ── xfce4-screensaver.xml — désactivé (inadapté OS enfant) ───────────
    cat > "$XFCONF_DIR/xfce4-screensaver.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="lock" type="empty">
    <property name="sleep-activation" type="bool" value="false"/>
    <property name="enabled" type="bool" value="false"/>
  </property>
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
</channel>
XMLEOF

    # ── xfce4-power-manager.xml — pas de mise en veille ni extinction écran
    cat > "$XFCONF_DIR/xfce4-power-manager.xml" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="power-button-action" type="uint" value="4"/>
    <property name="lid-action-on-battery" type="uint" value="1"/>
    <property name="lid-action-on-ac" type="uint" value="1"/>
    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="blank-on-battery" type="int" value="0"/>
    <property name="show-tray-icon" type="bool" value="false"/>
    <property name="show-panel-label" type="int" value="0"/>
  </property>
</channel>
XMLEOF
  '';

  # ── Autostart session init ───────────────────────────────────────────────────
  home.file.".config/autostart/apprendys-session-init.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Apprendys Session Init
    Exec=/home/apprendys/.local/bin/apprendys-session-init.sh
    Hidden=false
    NoDisplay=true
    X-GNOME-Autostart-enabled=true
  '';

  # ── Script session init — V1 fidèle avec sha256 checksum ────────────────────
  home.file.".local/bin/apprendys-session-init.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Apprendys session init — exécuté au démarrage de session XFCE

      # 1. Copier les icônes du profil actif vers la racine
      ICON_SET=$(cat "$HOME/.config/apprendys/icon-set" 2>/dev/null | tr -d '[:space:]')
      [ -z "$ICON_SET" ] && ICON_SET="junior"
      SRC="$HOME/.local/share/icons/apprendys/$ICON_SET"
      DST="$HOME/.local/share/icons/apprendys"
      if [ -d "$SRC" ]; then
        cp -f "$SRC"/*.png "$DST/" 2>/dev/null || true
      fi

      # 2. Briser les symlinks Nix store → fichiers réels writables (évite flèche + cadenas)
      # chmod 755 requis : gio set (xattr trusted) échoue sur fichier non-writable
      for f in "$HOME/Bureau/"*.desktop; do
        [ -f "$f" ] || continue
        if [ -L "$f" ] || [ ! -w "$f" ]; then
          cp --remove-destination "$(readlink -f "$f" 2>/dev/null || echo "$f")" "$f" 2>/dev/null || true
          chmod 755 "$f" 2>/dev/null || true
        fi
      done

      # Trust des .desktop bureau — attendre que GVfs soit prêt (max 15s)
      for i in $(seq 1 15); do
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

      # 3. Wallpaper dynamique — détecte le vrai nom du moniteur
      WALLPAPER="$HOME/.local/share/backgrounds/apprendys-wallpaper.png"
      if [ -f "$WALLPAPER" ]; then
        for monitor in $(xrandr --listmonitors 2>/dev/null | tail -n +2 | awk '{print $NF}'); do
          for ws in 0 1 2 3; do
            xfconf-query -c xfce4-desktop \
              -p "/backdrop/screen0/monitor''${monitor}/workspace''${ws}/last-image" \
              -s "$WALLPAPER" --create -t string 2>/dev/null || true
            xfconf-query -c xfce4-desktop \
              -p "/backdrop/screen0/monitor''${monitor}/workspace''${ws}/image-style" \
              -s 5 --create -t int 2>/dev/null || true
          done
        done
      fi

      # 4. Panel fond noir — xfce4-panel ignore background-color au démarrage,
      # on force via xfconf-query après que le panel soit actif
      xfconf-query -c xfce4-panel -p /panels/panel-1/background-style -t uint -s 1 --create 2>/dev/null || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/background-style -s 1 2>/dev/null || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/background-color -t string -s '#000000ff' --create 2>/dev/null || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/background-color -s '#000000ff' 2>/dev/null || true
      xfce4-panel --restart 2>/dev/null &

      # 5. Taille menu Whisker — 45% de la largeur écran, ratio 3:2
      SCREEN_W=$(xrandr --current 2>/dev/null | awk '/ connected.*[0-9]+x[0-9]+/{match($0,/[0-9]+x[0-9]+/); print substr($0,RSTART,RLENGTH)}' | cut -dx -f1 | head -1)
      if [ -n "$SCREEN_W" ] && [ "$SCREEN_W" -gt 0 ] 2>/dev/null; then
        MENU_W=$(( SCREEN_W * 45 / 100 ))
        MENU_H=$(( MENU_W * 67 / 100 ))
        xfconf-query -c xfce4-panel -p /plugins/plugin-1/menu-width -t int -s "$MENU_W" --create 2>/dev/null || true
        xfconf-query -c xfce4-panel -p /plugins/plugin-1/menu-height -t int -s "$MENU_H" --create 2>/dev/null || true
        xfconf-query -c xfce4-panel -p /plugins/plugin-1/menu-width -s "$MENU_W" 2>/dev/null || true
        xfconf-query -c xfce4-panel -p /plugins/plugin-1/menu-height -s "$MENU_H" 2>/dev/null || true
      fi

      # 5. Forcer les icônes bureau : style=2 (files) + pas d'icônes système
      # xfdesktop écrase les valeurs XML au démarrage → on les remet après
      xfconf-query -c xfce4-desktop -p /desktop-icons/style -t int -s 2 --create 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p /desktop-icons/icon-size -t uint -s 72 --create 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -t bool -s false --create 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-trash -t bool -s false --create 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -t bool -s false --create 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-removable -t bool -s false --create 2>/dev/null || true
      # Mettre à jour si la propriété existe déjà
      xfconf-query -c xfce4-desktop -p /desktop-icons/style -s 2 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -s false 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-trash -s false 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -s false 2>/dev/null || true
      xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-removable -s false 2>/dev/null || true

      # 5. Redémarrer xfdesktop pour appliquer trust + wallpaper + icônes corrigées
      pkill xfdesktop 2>/dev/null || true
      sleep 1
      xfdesktop &
    '';
  };

  # ── Config profil par défaut ─────────────────────────────────────────────────
  home.file.".config/apprendys/icon-set".text = "junior\n";

  # ── Thème GTK — Greybird (gris XFCE, reposant pour enfants DYS) ────────────
  gtk = {
    enable = true;
    theme = {
      name = "Greybird";
      package = pkgs.greybird;
    };
    iconTheme = {
      name = "elementary-xfce";
      package = pkgs.elementary-xfce-icon-theme;
    };
    font = {
      name = "Luciole";
      size = 13;
    };
  };

  # ── Bash ─────────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    shellAliases = {
      devoirs = "cd ~/Devoirs";
    };
  };
}
