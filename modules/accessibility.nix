{ config, pkgs, lib, ... }: {

  # Raccourcis clavier globaux TTS/STT (même bindings V1)
  # Ctrl+Espace = TTS (lit la sélection avec Piper)
  # Ctrl+Maj+Espace = STT (dictée Vosk)
  # Ces bindings sont configurés dans home/apprendys.nix via xfce4-keyboard-shortcuts

  # Services TTS/STT ne sont pas des daemons — lancés à la demande par scripts
  # apprendys-tts et apprendys-stt sont câblés dans modules/apps.nix

  environment.systemPackages = with pkgs; [
    piper-tts
    python3
    xsetroot
  ];

  # Activer les services d'accessibilité AT-SPI
  services.gnome.at-spi2-core.enable = true;
}
