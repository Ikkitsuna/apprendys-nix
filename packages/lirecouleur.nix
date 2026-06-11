{ lib, stdenvNoCC, fetchurl }:

# LireCouleur — extension LibreOffice DYS
# Source : https://extensions.libreoffice.org/en/extensions/show/lirecouleur
# Auteur : Marie-Pierre Brungard (CC-BY)
#
# L'extension .oxt est exposée dans $out/share/lirecouleur/lirecouleur.oxt
# Pour l'activer dans LibreOffice :
#   - Mode user : `unopkg add lirecouleur.oxt` (par user)
#   - Mode shared : déposer dans /run/current-system/sw/share/libreoffice/share/extensions/
#                   ou utiliser un module NixOS qui configure ça centralement

stdenvNoCC.mkDerivation rec {
  pname = "lirecouleur";
  version = "4.7";

  src = fetchurl {
    url = "https://extensions.libreoffice.org/assets/downloads/z/lirecouleur.oxt";
    sha256 = "1rbnfsjy4b7zjcgz5i5fvf9qbfq81lyv0mf8ny85yibjh95kbbl6";
  };

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/lirecouleur
    cp $src $out/share/lirecouleur/lirecouleur.oxt
    runHook postInstall
  '';

  meta = with lib; {
    description = "Extension LibreOffice pour aider à la lecture (DYS) — syllabes colorées, repères phonétiques";
    homepage = "https://lirecouleur.arkaline.fr/";
    license = licenses.cc-by-40;
    platforms = platforms.all;
  };
}
