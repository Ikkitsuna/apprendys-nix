{ lib, python3Packages, fetchurl, autoPatchelfHook, stdenv }:

# Vosk STT — absent de nixpkgs (juin 2026). Wheel PyPI avec libvosk.so embarquée.
# Wheel : vosk-0.3.45-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.whl
# requires_dist : cffi (>=1.0), requests, tqdm, srt, websockets
python3Packages.buildPythonPackage rec {
  pname = "vosk";
  version = "0.3.45";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/fc/ca/83398cfcd557360a3d7b2d732aee1c5f6999f68618d1645f38d53e14c9ff/vosk-${version}-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.whl";
    hash = "sha256-JeAlCTxDmdcnj1Q1aO2MxUYKw6S/SMI2c6zh4l0mYZ8=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  propagatedBuildInputs = with python3Packages; [ cffi requests srt tqdm websockets ];

  pythonImportsCheck = [ "vosk" ];

  meta = with lib; {
    description = "Reconnaissance vocale offline (Kaldi) — moteur dictée Apprendys";
    homepage = "https://alphacephei.com/vosk/";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}
