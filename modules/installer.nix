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

  # L'utilisateur live lance l'installateur sans mot de passe — UNIQUEMENT ce binaire.
  security.sudo.enable = lib.mkForce true;

  # Point délicat (cf. Task 9) : le script se ré-élève via
  #   exec sudo -n "$(command -v apprendys-installer)"
  # et `command -v` renvoie le SYMLINK systemPackages :
  #   /run/current-system/sw/bin/apprendys-installer
  # sudo applique la règle sur le chemin EXACT tel que tapé (il ne résout pas
  # le symlink avant de matcher). On autorise donc les DEUX chemins :
  #   - le symlink stable /run/current-system/sw/bin/... (celui réellement utilisé)
  #   - le chemin store ${apprendys-installer}/bin/... (robustesse)
  security.sudo.extraRules = [{
    users = [ "apprendys" ];
    commands = [
      {
        command = "/run/current-system/sw/bin/apprendys-installer";
        options = [ "NOPASSWD" "SETENV" ];
      }
      {
        command = "${apprendys-installer}/bin/apprendys-installer";
        options = [ "NOPASSWD" "SETENV" ];
      }
    ];
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
