{ config, pkgs, lib, ... }:
let
  luciole = pkgs.callPackage ../packages/luciole.nix {};
in {

  # Locale France — defaultLocale ne suffit PAS en mode ISO live :
  # certaines apps (Firefox, LibreOffice, GTK) lisent LC_MESSAGES directement,
  # pas LANG. Il faut forcer chaque LC_* explicitement.
  # Réunion par défaut (vente directe locale) ; NTP corrige le RTC au 1er WiFi. À rendre configurable à l'install quand la métropole scale.
  time.timeZone = "Indian/Reunion";
  i18n.defaultLocale = "fr_FR.UTF-8";
  i18n.supportedLocales = [
    "fr_FR.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
    "C.UTF-8/UTF-8"
  ];
  i18n.extraLocaleSettings = {
    LANG = "fr_FR.UTF-8";
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
    LC_MESSAGES = "fr_FR.UTF-8";  # crucial : traductions UI Firefox/LO/GTK
    LC_COLLATE = "fr_FR.UTF-8";
    LC_CTYPE = "fr_FR.UTF-8";
  };

  # Forcer les locales installées (pas seulement supportées)
  i18n.glibcLocales = pkgs.glibcLocales.override {
    allLocales = false;
    locales = [ "fr_FR.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" "C.UTF-8/UTF-8" ];
  };

  # Clavier AZERTY français
  services.xserver.xkb.layout = "fr";
  services.xserver.xkb.variant = "azerty";
  console.keyMap = "fr";

  # XFCE + SDDM avec autologin apprendys
  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "apprendys";
  };

  # Réseau
  networking.networkmanager.enable = true;

  # Son
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # SSH (production : désactivé sauf debug)
  services.openssh = {
    enable = lib.mkDefault false;
  };

  # Nix
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # L'enfant ne peut pas sudo (peut être overridé par dev-vm.nix)
  security.sudo.enable = lib.mkDefault false;

  # Utilisateur apprendys — autologin XFCE
  # initialPassword (au lieu de password) pour que SSH password auth fonctionne aussi
  users.users.apprendys = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "audio" "video" "networkmanager" "plugdev" "lp" ];
    initialPassword = "apprendys";
    shell = pkgs.bash;
    # Clé Florent pour debug/dev (à retirer en prod)
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINTm9zyJh4iYkeiNEIiUx7v/twH0e8IyTpz9DjwQRzCs florent@ArchWork"
    ];
  };

  # Prénom → nom complet du compte (GECOS) : le menu Whisker et SDDM affichent
  # le GECOS s'il existe, sinon « apprendys ». Deux sources, par priorité :
  #   1. ~/.config/apprendys/user-name  ← écrit par « Mon Apprendys » (valeur
  #      à jour ; n'existe qu'après le 1er login, seedé depuis /var/lib)
  #   2. /var/lib/apprendys/user-name   ← écrit par l'installateur (1er boot,
  #      avant tout login)
  # Lancé au boot (avant l'écran de connexion) ET déclenchable à chaud par
  # l'app quand on change le prénom (règle polkit ci-dessous). Sans fichier
  # (ISO live vierge) : no-op.
  systemd.services.apprendys-prenom = {
    description = "Applique le prénom Apprendys au compte (GECOS)";
    wantedBy = [ "multi-user.target" ];
    before = [ "display-manager.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for f in /home/apprendys/.config/apprendys/user-name \
               /var/lib/apprendys/user-name; do
        [ -f "$f" ] || continue
        # GECOS : pas de : ni , (séparateurs passwd), pas de contrôles, 32 max
        prenom=$(tr -d '\000-\037:,' < "$f" | head -c 32)
        [ -n "$prenom" ] || continue
        ${pkgs.shadow}/bin/usermod -c "$prenom" apprendys || true
        exit 0
      done
    '';
  };

  # « Mon Apprendys » (utilisateur apprendys) peut déclencher CE service
  # précis sans mot de passe, pour appliquer le prénom à chaud. polkit est
  # le mécanisme natif NixOS (pas de sudo sur le système installé).
  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "apprendys-prenom.service" &&
          action.lookup("verb") == "start" &&
          subject.user == "apprendys") {
        return polkit.Result.YES;
      }
    });
  '';

  # Fonts DYS — priorité absolue
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      luciole            # police DYS principale — CF-Informatik974
      open-dyslexic      # fallback DYS si Luciole indisponible
      liberation_ttf     # métriques compatibles Windows
      noto-fonts
      noto-fonts-color-emoji
    ];
    fontconfig.defaultFonts = {
      serif = [ "Luciole" "OpenDyslexic" "Liberation Serif" ];
      sansSerif = [ "Luciole" "OpenDyslexic" "Liberation Sans" ];
      monospace = [ "Liberation Mono" ];
    };
  };

  # NTFS pour P5 DEVOIRS (visible Windows)
  boot.supportedFilesystems = [ "ntfs" "vfat" "ext4" ];
  environment.systemPackages = with pkgs; [
    ntfs3g
    gvfs
    xdg-utils
  ];

  # ───────────────────────────────────────────────────────────────────
  # OPTIMISATIONS CLÉ USB — minimiser les écritures sur la NAND
  # Cf. PDF Architecture v13 § "Le moins possible la clé USB"
  # ───────────────────────────────────────────────────────────────────

  # ZRAM — swap compressé en RAM, OBLIGATOIRE
  # Un swapfile sur clé USB tuerait la NAND en quelques jours
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # journald en RAM — pas de logs persistants sur la flash
  services.journald.extraConfig = ''
    Storage=volatile
    RuntimeMaxUse=64M
  '';

  # /tmp en tmpfs (pas sur la clé)
  boot.tmp.useTmpfs = true;

  # swappiness à 0 — interdire l'usage de la clé comme swap
  # (zram absorbe les pics, pas de fallback disque)
  boot.kernel.sysctl = {
    "vm.swappiness" = 0;
    "vm.dirty_ratio" = 60;
    "vm.dirty_background_ratio" = 30;
    "vm.dirty_writeback_centisecs" = 6000;  # flush dirty pages toutes les 60s (vs 5s default)
  };

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "24.11";
}
