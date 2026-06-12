{ lib
, writeShellApplication
, piper-tts
, espeak-ng
, xsel
, xclip
, libnotify
, pulseaudio    # paplay
, coreutils
, findutils
, gawk          # calcul length_scale (vitesse)
, procps        # pkill
, piper-voice-fr-siwis    # voix par défaut, injectée par apps.nix
}:

# Apprendys TTS — Lire à voix haute
# Port NixOS du V1 patches/usr/local/bin/apprendys-tts.sh
# Ctrl+Espace : lit le texte sélectionné avec une voix IA française
#
# Détection voix :
#   1. /mnt/apprendys/models/tts/*.onnx (P4, upgrade premium sans rebuild)
#   2. ${piper-voice-fr-siwis}/share/piper-voices/fr-siwis-medium.onnx (Nix store, baked)
#   3. fallback espeak-ng (si tout échoue)

writeShellApplication {
  name = "apprendys-tts";
  runtimeInputs = [
    piper-tts espeak-ng xsel xclip libnotify pulseaudio coreutils findutils gawk procps
  ];
  text = ''
    set +e  # tolérance pannes — ne jamais crasher

    TMPWAV="/tmp/apprendys-tts-$$.wav"

    # Détection voix TTS : P4 upgrade prioritaire, fallback Nix store baked
    P4_TTS="/mnt/apprendys/models/tts"
    NIX_VOICE="${piper-voice-fr-siwis}/share/piper-voices/fr-siwis-medium.onnx"

    MODEL=""
    if [ -d "$P4_TTS" ]; then
      MODEL=$(find "$P4_TTS" -maxdepth 1 -name '*.onnx' -type f -print -quit 2>/dev/null || true)
    fi
    if [ -z "$MODEL" ] && [ -f "$NIX_VOICE" ]; then
      MODEL="$NIX_VOICE"
    fi

    # Récupérer le texte sélectionné
    TEXT=$(xsel -o 2>/dev/null || xclip -selection primary -o 2>/dev/null || true)
    if [ -z "$TEXT" ]; then
      TEXT="Sélectionne du texte, puis appuie sur le raccourci pour que je te le lise."
    fi

    # Tuer une lecture précédente
    pkill -f "paplay.*apprendys-tts" 2>/dev/null || true
    pkill -f "espeak-ng.*-v fr" 2>/dev/null || true

    # Vitesse réglée via Mon Apprendys (0.7 lente → 1.5 rapide, défaut 1.0).
    # Piper : length_scale = 1/vitesse (plus grand = plus lent).
    SPEED=$(cat "$HOME/.config/apprendys/tts-speed" 2>/dev/null || echo 1.0)
    LENGTH_SCALE=$(awk -v s="$SPEED" 'BEGIN{ if (s+0 < 0.5 || s+0 > 2) s=1; printf "%.2f", 1/s }')
    ESPEAK_WPM=$(awk -v s="$SPEED" 'BEGIN{ if (s+0 < 0.5 || s+0 > 2) s=1; printf "%d", 140*s }')

    # Piper (voix IA) avec fallback espeak-ng
    if [ -n "$MODEL" ] && command -v piper >/dev/null 2>&1; then
      if echo "$TEXT" | piper --model "$MODEL" --length_scale "$LENGTH_SCALE" --output_file "$TMPWAV" 2>/dev/null; then
        paplay "$TMPWAV" 2>/dev/null &
        ( sleep 30 && rm -f "$TMPWAV" ) &
      else
        espeak-ng -v fr -s "$ESPEAK_WPM" -p 50 "$TEXT" &
      fi
    else
      espeak-ng -v fr -s "$ESPEAK_WPM" -p 50 "$TEXT" &
    fi
  '';
}
