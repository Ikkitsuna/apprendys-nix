{ lib
, stdenv
, python3
, gobject-introspection
, gtk3
, wrapGAppsHook3
, xfconf          # xfconf-query
, xorg            # xrdb
, procps          # pgrep/pkill
, apprendys-session-init
}:

# Mon Apprendys — app de personnalisation + espace parent (PIN).
# Port V2 de la beta V1 (apprendys-profil.py). Voir packages/apprendys-app/.
#
# L'app écrit ~/.config/apprendys/{icon-set,user-name,font-style,font-size,
# cursor-size,tts-speed,parent-pin} — les MÊMES fichiers que session-init
# et apprendys-tts lisent. Source de vérité unique.

let
  pythonEnv = python3.withPackages (ps: [ ps.pygobject3 ]);
in
stdenv.mkDerivation {
  pname = "apprendys-app";
  version = "2.0.0";

  src = ./apprendys-app;

  nativeBuildInputs = [ wrapGAppsHook3 gobject-introspection ];
  buildInputs = [ gtk3 ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/apprendys $out/share/applications

    # Guides HTML + changelog embarqués (consultables hors-ligne)
    cp -r ${../assets/guides} $out/share/apprendys/guides
    cp ${../assets/CHANGELOG.json} $out/share/apprendys/CHANGELOG.json

    # Script principal : chemins data substitués + shebang python env
    substitute apprendys-app.py $out/bin/apprendys-app \
      --replace-fail '@changelog@' "$out/share/apprendys/CHANGELOG.json" \
      --replace-fail '@guides@'    "$out/share/apprendys/guides"
    sed -i "1s|.*|#!${pythonEnv}/bin/python3|" $out/bin/apprendys-app
    chmod +x $out/bin/apprendys-app

    # Entrée de menu (catégorie Réglages du Whisker)
    substitute ${./apprendys-app/apprendys-app.desktop} \
      $out/share/applications/apprendys-app.desktop \
      --replace-fail '@out@' "$out"

    runHook postInstall
  '';

  # Outils requis au runtime (xfconf-query, xrdb, pkill, session-init)
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [ xfconf xorg.xrdb procps apprendys-session-init ]}
    )
  '';

  meta = with lib; {
    description = "Mon Apprendys — personnalisation et espace parent";
    license = licenses.unfree;   # code propriétaire CF-Informatik974
    platforms = platforms.linux;
  };
}
