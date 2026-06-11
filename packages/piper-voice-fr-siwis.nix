{ lib, stdenvNoCC, fetchurl }:

# Voix Piper FR — fr_FR-siwis-medium
# Source : Hugging Face rhasspy/piper-voices
# Validée terrain V1 (V14 squashfs baked)
#
# Installée dans :
#   $out/share/piper-voices/fr-siwis-medium.onnx
#   $out/share/piper-voices/fr-siwis-medium.onnx.json
#
# Le wrapper apprendys-tts cherche d'abord dans /mnt/apprendys/models/tts/ (P4 override)
# puis dans /run/current-system/sw/share/piper-voices/ (Nix store) en fallback.

stdenvNoCC.mkDerivation {
  pname = "piper-voice-fr-siwis-medium";
  version = "1.0";

  srcOnnx = fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx";
    sha256 = "16dg7fkn8al02hc3iqwbrkg8bcsjn3ni0s07ih982aysjyq1l7b4";
  };

  srcJson = fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx.json";
    sha256 = "0nc9vzj3lqy0frlhr2dd4gh86kbl1kfsskbnr5d2n6fvq8b9jirr";
  };

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/piper-voices
    cp "$srcOnnx" $out/share/piper-voices/fr-siwis-medium.onnx
    cp "$srcJson" $out/share/piper-voices/fr-siwis-medium.onnx.json
    runHook postInstall
  '';

  meta = with lib; {
    description = "Voix Piper TTS française (Siwis, qualité medium ~80MB)";
    homepage = "https://huggingface.co/rhasspy/piper-voices";
    license = licenses.cc-by-40;
    platforms = platforms.all;
  };
}
