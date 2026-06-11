{ config, pkgs, lib, ... }: {
  # Profil pro — PC récent (≥8Go RAM), Whisper small
  networking.hostName = "apprendys";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.systemd-boot.configurationLimit = 3;

  # Whisper small (modèle ~150Mo, baked dans P3 ou P4)
  environment.variables.APPRENDYS_STT_MODEL = "/mnt/apprendys/models/stt";
  environment.variables.APPRENDYS_TTS_MODEL = "/mnt/apprendys/models/tts";
  environment.variables.APPRENDYS_PROFILE = "pro";

  environment.systemPackages = with pkgs; [
    # Whisper nécessite faster-whisper ou whisper-cpp
    # TODO: package whisper-cpp
  ];
}
