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
    LOCKDIR="/tmp/apprendys-stt.lock"
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

    # --- Section critique : verrou anti double-appui (mkdir = atomique POSIX) ---
    if ! mkdir "$LOCKDIR" 2>/dev/null; then
      exit 0   # une autre invocation est en cours (double-appui) — on ignore
    fi
    trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

    # Toggle : déjà en cours → on arrête
    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      # Guard : rejeter un PID non numérique (fichier corrompu après crash)
      case "$PID" in (*[!0-9]*|"") PID="" ;; esac
      if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        rm -f "$PIDFILE"
        notify-send -i audio-input-microphone "Dictée terminée" "Le micro est éteint." -t 2000
        exit 0   # trap releases LOCKDIR
      fi
      rm -f "$PIDFILE"
    fi

    notify-send -i audio-input-microphone "Dictée activée !" "Parle, j'écris pour toi.
Appuie encore pour arrêter." -t 3000

    export VOSK_MODEL

    python3 -u << 'ENDPY' &
import json, subprocess, sys, os, signal, ctypes

# Fix 3 : arecord meurt avec python même en cas de kill -9 (PDEATHSIG)
PR_SET_PDEATHSIG = 1
libc = ctypes.CDLL("libc.so.6", use_errno=True)
def _die_with_parent():
    libc.prctl(PR_SET_PDEATHSIG, signal.SIGTERM)

# Fix 4 : guard chargement modèle
try:
    from vosk import Model, KaldiRecognizer
    model = Model(os.environ["VOSK_MODEL"])
    rec = KaldiRecognizer(model, 16000)
except Exception as e:
    print(f"apprendys-stt: erreur chargement modèle: {e}", file=sys.stderr)
    sys.exit(1)

proc = subprocess.Popen(
    ["arecord", "-f", "S16_LE", "-r", "16000", "-c", "1", "-t", "raw", "-q"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    preexec_fn=_die_with_parent)

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
        # Fix 4 : guard résultat JSON malformé
        try:
            text = json.loads(rec.Result()).get("text", "").strip()
        except (ValueError, KeyError):
            continue
        if text:
            subprocess.run(["xdotool", "type", "--delay", "20", text + " "],
                           env={**os.environ, "DISPLAY": os.environ.get("DISPLAY", ":0")})
ENDPY

    STT_PID=$!
    echo "$STT_PID" > "$PIDFILE"

    # Libérer le verrou AVANT wait : une invocation ultérieure doit pouvoir
    # entrer dans la section critique pour toggler l'arrêt.
    trap - EXIT
    rmdir "$LOCKDIR" 2>/dev/null

    wait "$STT_PID" 2>/dev/null
    rm -f "$PIDFILE"
  '';
}
