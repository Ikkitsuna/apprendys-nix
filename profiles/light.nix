{ config, pkgs, lib, ... }: {
  # Profil light — vieux PC (≥4Go RAM), Vosk small
  networking.hostName = "apprendys";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.systemd-boot.configurationLimit = 2;

  # Vosk small (modèle < 100Mo, baked dans P3)
  environment.variables.APPRENDYS_STT_MODEL = "/opt/vosk/model-fr";
  environment.variables.APPRENDYS_TTS_MODEL = "/opt/piper/fr-siwis-medium.onnx";
  environment.variables.APPRENDYS_PROFILE = "light";

  # SSH activé temporairement pour debug ISO en VM
  # À RETIRER en prod (passer par Couche A patches si besoin)
  services.openssh = {
    enable = lib.mkForce true;
    settings.PasswordAuthentication = true;
    settings.PermitRootLogin = "no";
  };
  # User apprendys peut sudo pour debug
  security.sudo.enable = lib.mkForce true;
  security.sudo.wheelNeedsPassword = false;
  users.users.apprendys.extraGroups = [ "wheel" ];

  # Pas de compositing sur vieux PC
  # (déjà désactivé dans home/apprendys.nix via xfwm4 xfconf)
}
