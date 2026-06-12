{ config, pkgs, lib, ... }: {
  # OTA Apprendys installé — MAJ silencieuse hebdomadaire.
  # Atomique : nouvelle génération NixOS ; si régression → rollback au menu GRUB
  # (configurationLimit = 5 défini dans profiles/installed.nix).
  # Les flakes sont activés dans base.nix (nix.settings.experimental-features).

  systemd.services.apprendys-ota = {
    description = "Apprendys — mise à jour système (nixos-rebuild)";
    # Réseau nécessaire pour joindre github.com ; wants (pas requires) pour
    # ne pas faire échouer le rattrapage Persistent si le réseau est absent.
    after  = [ "network-online.target" ];
    wants  = [ "network-online.target" ];
    serviceConfig = { Type = "oneshot"; };
    path = [ pkgs.nixos-rebuild pkgs.nix pkgs.git pkgs.coreutils ];
    script = ''
      # Pile CMOS morte → année fausse → SSL cassé (bug terrain V1) : on saute.
      [ "$(date +%Y)" -ge 2026 ] || exit 0

      nixos-rebuild switch \
        --flake github:Ikkitsuna/apprendys-nix#apprendys-installed \
        --refresh \
        || echo "apprendys-ota: échec (réseau ?) — prochaine tentative au timer"
    '';
  };

  systemd.timers.apprendys-ota = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar        = "weekly";
      Persistent        = true;   # rattrape si le PC était éteint lors du déclenchement
      RandomizedDelaySec = "2h";
    };
  };

  # Bouton « Vérifier maintenant » de Mon Apprendys (espace parent PIN) :
  # polkit (comme la V1, 50-apprendys-update.rules) — pas de sudo sur le
  # système installé. Seul le START de CE service précis est autorisé.
  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "apprendys-ota.service" &&
          action.lookup("verb") == "start" &&
          subject.user == "apprendys") {
        return polkit.Result.YES;
      }
    });
  '';
}
