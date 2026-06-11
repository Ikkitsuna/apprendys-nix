{ lib
, writeShellApplication
, python3
, vosk                     # packages/vosk.nix, injecté par apps.nix
, vosk-model-fr-small      # packages/vosk-model-fr-small.nix, injecté par apps.nix
, alsa-utils               # arecord
, xdotool
, libnotify
, coreutils
, procps
}:

# Apprendys STT — Le Perroquet (dictée vocale offline)
# Port NixOS de V1 patches/usr/local/bin/apprendys-stt.sh
# Ctrl+Maj+Espace : toggle dictée — parle, le texte est tapé au curseur.
#
# Modèle : 1. /mnt/apprendys/models/stt (P4/premium, sans .bin = Vosk)
#          2. Nix store (baked) — vosk-model-fr-small

let pythonVosk = python3.withPackages (ps: [ vosk ]);
in writeShellApplication {
  name = "apprendys-stt";
  runtimeInputs = [ pythonVosk alsa-utils xdotool libnotify coreutils procps ];
  text = ''
    set +e   # tolérance pannes — jamais crasher devant l'enfant

    PIDFILE="/tmp/apprendys-stt.pid"
    P4_STT="/mnt/apprendys/models/stt"
    NIX_MODEL="${vosk-model-fr-small}/share/vosk-models/fr-small"

    if [ -d "$P4_STT" ] && [ -n "$(ls -A "$P4_STT" 2>/dev/null)" ] && ! ls "$P4_STT"/*.bin >/dev/null 2>&1; then
      VOSK_MODEL="$P4_STT"
    elif [ -d "$NIX_MODEL" ]; then
      VOSK_MODEL="$NIX_MODEL"
    else
      notify-send -i dialog-error "Erreur Dictée" "Modèle vocal non trouvé." -t 3000
      exit 1
    fi

    # Toggle : déjà en cours → on arrête
    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        rm -f "$PIDFILE"
        notify-send -i audio-input-microphone "Dictée terminée" "Le micro est éteint." -t 2000
        exit 0
      fi
      rm -f "$PIDFILE"
    fi

    notify-send -i audio-input-microphone "Dictée activée !" "Parle, j'écris pour toi.
Appuie encore pour arrêter." -t 3000

    export VOSK_MODEL

    python3 -u << 'ENDPY' &
import json, subprocess, sys, os, signal
from vosk import Model, KaldiRecognizer

model = Model(os.environ["VOSK_MODEL"])
rec = KaldiRecognizer(model, 16000)
proc = subprocess.Popen(
    ["arecord", "-f", "S16_LE", "-r", "16000", "-c", "1", "-t", "raw", "-q"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

def cleanup(sig, frame):
    proc.terminate()
    sys.exit(0)
signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

while True:
    data = proc.stdout.read(4000)
    if len(data) == 0:
        break
    if rec.AcceptWaveform(data):
        text = json.loads(rec.Result()).get("text", "").strip()
        if text:
            subprocess.run(["xdotool", "type", "--delay", "20", text + " "],
                           env={**os.environ, "DISPLAY": os.environ.get("DISPLAY", ":0")})
ENDPY

    STT_PID=$!
    echo "$STT_PID" > "$PIDFILE"
    wait "$STT_PID" 2>/dev/null
    rm -f "$PIDFILE"
  '';
}
