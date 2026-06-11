{ lib, stdenvNoCC, fetchurl, python3 }:

stdenvNoCC.mkDerivation {
  pname = "luciole";
  version = "2024";

  src = fetchurl {
    url = "https://www.luciole-vision.com/fonts/Luciole.zip";
    sha256 = "18im4z1fd6wln941r3byhvkyp80x0ky1kwnlnl6sm9pg6qa0q003";
  };

  nativeBuildInputs = [ python3 ];

  unpackPhase = ''
    python3 -c "
import zipfile, os
z = zipfile.ZipFile('$src')
for f in z.namelist():
    if f.endswith('.ttf') and not f.startswith('__MACOSX'):
        data = z.read(f)
        name = os.path.basename(f)
        open(name, 'wb').write(data)
"
  '';

  installPhase = ''
    mkdir -p $out/share/fonts/truetype/luciole
    install -Dm644 *.ttf $out/share/fonts/truetype/luciole/
  '';

  meta = {
    description = "Luciole — police conçue pour les malvoyants et les personnes DYS";
    homepage = "https://www.luciole-vision.com";
    license = lib.licenses.cc-by-40;
    platforms = lib.platforms.all;
  };
}
