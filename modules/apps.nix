{ config, pkgs, lib, ... }:
let
  piper-voice-fr-siwis = pkgs.callPackage ../packages/piper-voice-fr-siwis.nix {};
  lirecouleur = pkgs.callPackage ../packages/lirecouleur.nix {};
  apprendys-tts = pkgs.callPackage ../packages/apprendys-tts.nix {
    inherit piper-voice-fr-siwis;
  };
  vosk = pkgs.callPackage ../packages/vosk.nix {};
  vosk-model-fr-small = pkgs.callPackage ../packages/vosk-model-fr-small.nix {};
  apprendys-stt = pkgs.callPackage ../packages/apprendys-stt.nix {
    inherit vosk vosk-model-fr-small;
  };
  apprendys-session-init = pkgs.callPackage ../packages/apprendys-session-init.nix {
    inherit lirecouleur;
    xrandr = pkgs.xorg.xrandr;
  };
in {

  # Forcer l'inclusion des données partagées (piper-voices, lirecouleur, vosk-model)
  # qui sont des paquets share/-only — non inclus par iso-image.nix par défaut
  system.extraDependencies = [ piper-voice-fr-siwis lirecouleur vosk-model-fr-small ];
  environment.pathsToLink = [ "/share/piper-voices" "/share/lirecouleur" "/share/vosk-models" ];

  environment.systemPackages = with pkgs; [
    # Outils bureau Apprendys
    xournalpp            # Mes Devoirs — PDF annoté, équerre, formes
    libreoffice-fresh    # Mes Leçons — Writer + LireCouleur
    firefox              # Je Recherche
    chromium             # Je Recherche (alternatif)

    # Localisation FR (paquets de traduction)
    hunspellDicts.fr-any            # correction orthographique FR
    aspellDicts.fr                  # idem aspell

    # Outils système XFCE
    thunar
    thunar-volman
    xfce4-terminal
    xfce4-power-manager
    xfce4-pulseaudio-plugin
    xfce4-whiskermenu-plugin
    xfce4-notifyd
    # xfce4-screensaver retiré — verrouillage inadapté pour un OS enfant

    # Session init Apprendys (autostart XFCE)
    apprendys-session-init   # icon-set, LireCouleur unopkg, locks stale, desktop trust

    # Accessibilité — TTS / STT
    apprendys-tts            # wrapper Piper + espeak fallback (Ctrl+Espace)
    piper-tts                # binaire Piper (utilisé par apprendys-tts)
    piper-voice-fr-siwis     # voix FR siwis (~80MB) — validée terrain V14
    espeak-ng                # fallback TTS
    apprendys-stt            # Le Perroquet — dictée Vosk offline (Ctrl+Maj+Espace)
    vosk-model-fr-small      # modèle FR small (~50MB) — baked dans le store

    # LibreOffice — extension DYS LireCouleur (à activer manuellement
    # ou via un service NixOS post-install)
    lirecouleur

    # Utilitaires
    pavucontrol          # Mixer audio
    xdotool              # Raccourcis clavier scriptables (TTS/STT)
    xsel                 # Copie sélection pour TTS
    xclip
    libnotify

    # Divers
    wget curl
  ];

  # Firefox — politique centralisée (remplace patches/etc/firefox/)
  programs.firefox = {
    enable = true;
    languagePacks = [ "fr" ];   # UI Firefox en français (sinon UI en EN)
    policies = {
      DisableAppUpdate = true;
      DisableTelemetry = true;
      DisableFirefoxAccounts = true;
      NoDefaultBookmarks = true;
      # Force locale FR au démarrage (au cas où le languagePack ne suffit pas)
      RequestedLocales = [ "fr" "en-US" ];
      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
          default_installation_mode = "force_installed";
        };
        "VH@unhook.app" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/youtube-recommended-videos/latest.xpi";
          installation_mode = "force_installed";
        };
      };
      Preferences = {
        "browser.startup.homepage" = { Value = "about:newtab"; Status = "locked"; };
        "browser.newtabpage.activity-stream.showSponsored" = { Value = false; Status = "locked"; };
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = { Value = false; Status = "locked"; };
      };
    };
  };

  # Chromium — politique centralisée (remplace patches/etc/chromium/)
  programs.chromium = {
    enable = true;
    extraOpts = {
      "DefaultSearchProviderEnabled" = true;
      "DefaultSearchProviderName" = "Ecosia";
      "DefaultSearchProviderSearchURL" = "https://www.ecosia.org/search?q={searchTerms}";
      "DownloadDirectory" = "/home/apprendys/Devoirs";
    };
  };
}
