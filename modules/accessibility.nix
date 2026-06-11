{ config, pkgs, lib, ... }: {

  # Raccourcis clavier globaux TTS/STT (même bindings V1)
  # Ctrl+Espace = TTS (lit la sélection avec Piper)
  # Ctrl+Maj+Espace = STT (dictée Vosk)
  # Ces bindings sont configurés dans home/apprendys.nix via xfce4-keyboard-shortcuts

  # Services TTS/STT ne sont pas des daemons — lancés à la demande par scripts
  # Les scripts apprendys-tts.sh / apprendys-stt.sh sont déployés dans /usr/local/bin

  environment.systemPackages = with pkgs; [
    # TTS
    piper-tts

    # STT — Vosk n'est pas dans nixpkgs; à packager en mkDerivation custom
    # TODO: packages/vosk.nix — fetchurl depuis vosk-api releases
    python3
    python3Packages.pyaudio

    # Accessibilité curseur
    xsetroot
  ];

  # Activer les services d'accessibilité AT-SPI
  services.gnome.at-spi2-core.enable = true;
}
