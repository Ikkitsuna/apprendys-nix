{ config, pkgs, lib, ... }:

# GnuRAMage V2 — Couche userland (sync sélective home → P4)
#
# Rôle V2 : protège les écritures actives userland (XFCE config, Firefox profile).
# Le système (Nix store) est immuable nativement → pas besoin de le couvrir.
# La persistance système (NM, BT, machine-id) est gérée par impermanence (persistence.nix).
#
# Principe (cf. PDF Architecture v13 + repo FPGArtktic/GnuRAMage) :
#   1. Au boot : copie P4_PERSIST/home/apprendys → /home/apprendys (tmpfs RAM)
#   2. Boucle : sync sélective tmpfs → P4 toutes les 180s (whitelist)
#   3. Au shutdown : sync final
#
# Activation : `apprendys.gnuramage.enable = true;` dans le profil USB
# Désactivé par défaut (VM dev n'en a pas besoin)

let
  cfg = config.apprendys.gnuramage;
in {
  options.apprendys.gnuramage = {
    enable = lib.mkEnableOption "GnuRAMage userland sync (home tmpfs ↔ P4)";

    persistRoot = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/apprendys/persist";
      description = "Chemin de la racine persistante sur P4";
    };

    syncInterval = lib.mkOption {
      type = lib.types.int;
      default = 180;
      description = "Intervalle de sync RAM → P4 (secondes)";
    };

    # Whitelist : seuls ces sous-chemins de /home/apprendys sont synchronisés
    # Exclut volontairement : caches, modèles IA, logs, .gnupg
    homeWhitelist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        ".config/xfce4"          # config bureau (panel, fond, raccourcis)
        ".config/Mousepad"       # éditeur texte
        ".config/apprendys"      # nos préférences custom (font-name, .channel)
        ".config/gtk-3.0"        # bookmarks Thunar
        ".config/pulse"          # volume audio
        ".local/share/xfce4"
        ".local/share/applications"
        ".mozilla/firefox"        # Firefox profile (sans cache)
        "Bureau"                  # raccourcis bureau
      ];
      description = "Sous-chemins de /home/apprendys synchronisés vers P4";
    };
  };

  config = lib.mkIf cfg.enable {
    # /home/apprendys vit en tmpfs (RAM) — gnuramage gère la persistance
    # NB : impermanence ne doit PAS persister /home/apprendys quand gnuramage est actif
    fileSystems."/home/apprendys" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "defaults" "size=1G" "mode=755" "uid=1000" "gid=100" ];
      neededForBoot = true;
    };

    systemd.services.gnuramage = {
      description = "GnuRAMage — sync sélective home tmpfs → P4 (protection NAND)";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" "home-apprendys.mount" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";
        # Sync final au shutdown
        ExecStop = pkgs.writeShellScript "gnuramage-stop" ''
          ${pkgs.rsync}/bin/rsync -a --delete /home/apprendys/ "${cfg.persistRoot}/home/apprendys/" 2>/dev/null || true
        '';
      };
      script = ''
        set +e  # ne jamais crasher (tolérance pannes)
        TMPFS="/home/apprendys"
        PERSIST="${cfg.persistRoot}/home/apprendys"
        WHITELIST="${lib.concatStringsSep " " cfg.homeWhitelist}"

        mkdir -p "$PERSIST"
        chown apprendys:users "$PERSIST" 2>/dev/null || true

        # Phase 1 : seed initial P4 → tmpfs (au boot, le tmpfs est vide)
        if [ -d "$PERSIST" ] && [ -z "$(ls -A "$TMPFS" 2>/dev/null)" ]; then
          ${pkgs.rsync}/bin/rsync -a "$PERSIST/" "$TMPFS/" 2>/dev/null || true
          chown -R apprendys:users "$TMPFS" 2>/dev/null || true
        fi

        # Phase 2 : boucle de sync tmpfs → P4 (whitelist uniquement)
        while true; do
          sleep ${toString cfg.syncInterval}
          for path in $WHITELIST; do
            src="$TMPFS/$path"
            dst="$PERSIST/$path"
            if [ -e "$src" ]; then
              mkdir -p "$(dirname "$dst")"
              ${pkgs.rsync}/bin/rsync -a --delete "$src/" "$dst/" 2>/dev/null || \
              ${pkgs.rsync}/bin/rsync -a --delete "$src" "$dst" 2>/dev/null || true
            fi
          done
        done
      '';
    };
  };
}
