{ lib, stdenvNoCC, fetchzip }:

# Modèle Vosk FR small — vosk-model-small-fr-0.22
# Source : https://alphacephei.com/vosk/models
# Validé terrain V1 (V14 squashfs baked, validé Blackview)
#
# Installé dans : $out/share/vosk-models/fr-small/
# Le wrapper apprendys-stt cherche d'abord dans /mnt/apprendys/models/stt/ (P4 override)
# puis dans /run/current-system/sw/share/vosk-models/fr-small/ (Nix store) en fallback.

stdenvNoCC.mkDerivation {
  pname = "vosk-model-fr-small";
  version = "0.22";

  src = fetchzip {
    url = "https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip";
    sha256 = "16j0bmki6ws3nwj0yhkkzcha3qfdnxns6hikj4n522bpspnyr3dz";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/vosk-models/fr-small
    cp -r ./* $out/share/vosk-models/fr-small/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Modèle Vosk français — small (~50 MB, optimisé clés USB)";
    homepage = "https://alphacephei.com/vosk/models";
    license = licenses.asl20;
    platforms = platforms.all;
  };
}
